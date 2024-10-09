-module(node1).
-export([start/1, start/2, init/2, node/3]).
-define(STABILIZE_INTERVAL, 1000).
-define(TIMEOUT, 10000).

start(Id) ->
    start(Id, nil).

start(Id, Peer) ->
    spawn(fun() -> init(Id, Peer) end).

init_node(Id) ->
    Self = self(),
    schedule_stabilize(),
    node(Id, nil, {Id, Self}).

init(Id, Peer) ->
    Predecessor = nil,
    {ok, Successor} = connect(Id, Peer),
    schedule_stabilize(),
    node(Id, Predecessor, Successor).

schedule_stabilize() ->
    timer:send_interval(?STABILIZE_INTERVAL, {stabilize}).

node(Id, Predecessor, Successor) ->
    receive
        {key, Qref, Peer} ->
            io:format("Node ~p: Received {key, ~p, ~p}~n", [Id, Qref, Peer]),
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor);
        {notify, New} ->
            io:format("Node ~p: Received {notify, ~p}~n", [Id, New]),
            Pred = notify(New, Id, Predecessor),
            node(Id, Pred, Successor);
        {request, Peer} ->
            request(Peer, Predecessor),
            node(Id, Predecessor, Successor);
        {status, Pred} ->
            io:format("Node ~p: Received {status, ~p}~n", [Id, Pred]),
            Succ = stabilize(Pred, Id, Successor),
            node(Id, Predecessor, Succ);
        {stabilize} ->
            io:format("Node ~p: Periodic stabilization triggered.~n", [Id]),
            stabilize(Successor),
            node(Id, Predecessor, Successor);
        {print_state} ->
            io:format("Node ~p: State => Predecessor: ~p, Successor: ~p~n", [
                Id, Predecessor, Successor
            ]),
            node(Id, Predecessor, Successor);
        {probe} ->
            create_probe(Id, Successor),
            node(Id, Predecessor, Successor);
        {probe, Id, Nodes, T} ->
            remove_probe(T, Nodes),
            node(Id, Predecessor, Successor);
        {probe, Ref, Nodes, T} ->
            forward_probe(Ref, T, Nodes, Id, Successor),
            node(Id, Predecessor, Successor);
        {terminate} ->
            io:format("Node ~p: Terminating.~n", [Id]),
            ok;
        Other ->
            io:format("Node ~p: Received unknown message: ~p~n", [Id, Other]),
            node(Id, Predecessor, Successor)
    end.

notify({Nkey, Npid}, Id, Predecessor) ->
    case Predecessor of
        nil ->
            {Nkey, Npid};
        {Pkey, _} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    {Nkey, Npid};
                false ->
                    Predecessor
            end
    end.

stabilize(Successor) ->
    {_, Spid} = Successor,
    io:format("Node ~p: Sending {request, self()} to Successor ~p~n", [self(), Spid]),
    Spid ! {request, self()}.

stabilize(Pred, Id, Successor) ->
    io:format("Node ~p: Stabilizing with Pred=~p, Successor=~p~n", [Id, Pred, Successor]),
    {Skey, Spid} = Successor,
    case Pred of
        nil ->
            io:format("Node ~p: Successor's predecessor is nil, notifying successor.~n", [Id]),
            Spid ! {notify, {Id, self()}},
            Successor;
        {Id, _} ->
            io:format("Node ~p: Successor's predecessor is us, no action needed.~n", [Id]),
            Successor;
        {Skey, _} ->
            io:format("Node ~p: Successor's predecessor is itself, notifying successor.~n", [Id]),
            Spid ! {notify, {Id, self()}},
            Successor;
        {Xkey, Xpid} ->
            io:format("Node ~p: Successor's predecessor is node ~p.~n", [Id, Xkey]),
            case key:between(Xkey, Id, Skey) of
                true ->
                    io:format("Node ~p: Xkey ~p is between our Id ~p and Successor's key ~p.~n", [
                        Id, Xkey, Id, Skey
                    ]),
                    NewSuccessor = {Xkey, Xpid},
                    io:format("Node ~p: Updating Successor to ~p.~n", [Id, NewSuccessor]),
                    NewSuccessor;
                false ->
                    io:format(
                        "Node ~p: Xkey ~p is not between our Id ~p and Successor's key ~p, notifying successor.~n",
                        [Id, Xkey, Id, Skey]
                    ),
                    Spid ! {notify, {Id, self()}},
                    Successor
            end
    end.

request(Peer, Predecessor) ->
    io:format("Node ~p: Received {request, ~p}~n", [self(), Peer]),
    io:format("Node ~p: Sending {status, ~p} to ~p~n", [self(), Predecessor, Peer]),
    Peer ! {status, Predecessor}.

connect(Id, nil) ->
    Self = self(),
    {ok, {Id, Self}};
connect(Id, Peer) ->
    Qref = make_ref(),
    Peer ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            {ok, {Skey, Peer}}
    after ?TIMEOUT ->
        io:format("Node ~p: Timeout while connecting to peer~n", [Id]),
        {error, timeout}
    end.

create_probe(Id, Successor) ->
    T = erlang:system_time(micro_seconds),
    Nodes = [self()],
    {Skey, Spid} = Successor,
    io:format("Node ~p: Creating probe at time ~p~n", [Id, T]),
    Spid ! {probe, Id, Nodes, T}.

forward_probe(Ref, T, Nodes, Id, Successor) ->
    io:format("Node ~p: Forwarding probe originated by ~p~n", [Id, Ref]),
    Nodes1 = [self() | Nodes],
    {Skey, Spid} = Successor,
    Spid ! {probe, Ref, Nodes1, T}.

remove_probe(T, Nodes) ->
    Tnow = erlang:system_time(micro_seconds),
    TimeTaken = Tnow - T,
    io:format("Probe completed. Time taken: ~p microseconds~n", [TimeTaken]),
    io:format("Nodes visited: ~p~n", [lists:reverse(Nodes)]).
