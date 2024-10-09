%% File: dht_test.erl
-module(dht_test).
-export([start_ring/2, run_clients/3, perform_test/4]).

%% Include necessary modules
-compile([{parse_transform, sys_pre_attributes}]).

start_ring(NumNodes, StartId) ->
    Ids = [StartId + N || N <- lists:seq(0, NumNodes - 1)],
    NodeNames = [list_to_atom("node" ++ integer_to_list(N)) || N <- lists:seq(1, NumNodes)],
    NodePids = start_nodes_distributed(Ids, NodeNames, undefined),
    NodePids.

start_nodes_distributed([], [], _PrevNodePid) ->
    [];
start_nodes_distributed([Id | Ids], [NodeName | NodeNames], PrevNodePid) ->
    %% Start the slave node
    {ok, Node} = slave:start('localhost', NodeName, []),
    %% Ensure code is loaded on the slave node
    %% Copy code paths from master node to slave node
    add_code_paths(Node),
    %% Load necessary modules on the slave node
    rpc:call(Node, code, load_file, [key]),
    rpc:call(Node, code, load_file, [storage]),
    rpc:call(Node, code, load_file, [node4]),
    %% Start the node on the slave node
    Pid =
        case PrevNodePid of
            undefined ->
                rpc:call(Node, node4, start, [Id]);
            _ ->
                rpc:call(Node, node4, start, [Id, PrevNodePid])
        end,
    %% Connect the nodes
    [Pid | start_nodes_distributed(Ids, NodeNames, Pid)].

add_code_paths(Node) ->
    %% Get the code paths from the master node
    Paths = code:get_path(),
    %% Add each path to the slave node
    lists:foreach(
        fun(Path) ->
            rpc:call(Node, code, add_pathz, [Path])
        end,
        Paths
    ).

run_clients(NumClients, NumKeys, NodePids) ->
    ClientIds = lists:seq(1, NumClients),
    [spawn(fun() -> client_loop(ClientId, NumKeys, NodePids) end) || ClientId <- ClientIds].

client_loop(ClientId, NumKeys, NodePids) ->
    RandomNodePid = lists:nth(rand:uniform(length(NodePids)), NodePids),
    Keys = [rand:uniform(1000000) + ClientId * 1000000 || _ <- lists:seq(1, NumKeys)],
    T1 = erlang:monotonic_time(millisecond),
    lists:foreach(
        fun(Key) ->
            Qref = make_ref(),
            RandomNodePid ! {add, Key, {client, ClientId, Key}, Qref, self()},
            receive
                {Qref, ok} -> ok
            after 5000 -> io:format("Client ~p: Add timed out for key ~p~n", [ClientId, Key])
            end
        end,
        Keys
    ),
    T2 = erlang:monotonic_time(millisecond),
    AddTime = T2 - T1,
    io:format("Client ~p: Added ~p keys in ~p ms~n", [ClientId, NumKeys, AddTime]),
    T3 = erlang:monotonic_time(millisecond),
    lists:foreach(
        fun(Key) ->
            Qref = make_ref(),
            RandomNodePid ! {lookup, Key, Qref, self()},
            receive
                {Qref, {Key, _Value}} -> ok;
                {Qref, false} -> io:format("Client ~p: Key ~p not found~n", [ClientId, Key])
            after 5000 -> io:format("Client ~p: Lookup timed out for key ~p~n", [ClientId, Key])
            end
        end,
        Keys
    ),
    T4 = erlang:monotonic_time(millisecond),
    LookupTime = T4 - T3,
    io:format("Client ~p: Looked up ~p keys in ~p ms~n", [ClientId, NumKeys, LookupTime]).

perform_test(NumNodes, NumClients, NumKeys, StartId) ->
    NodePids = start_ring(NumNodes, StartId),
    %% Wait for nodes to stabilize
    timer:sleep(5000),
    run_clients(NumClients, NumKeys, NodePids),
    ok.
