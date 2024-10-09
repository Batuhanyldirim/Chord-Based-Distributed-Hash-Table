-module(node4).
-export([start/1, start/2, init/2, node/6]).
-define(STABILIZE_INTERVAL, 1000).
-define(TIMEOUT, 10000).

start(Id) ->
    start(Id, nil).

start(Id, Peer) ->
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    Store = storage:create(),
    Replica = storage:create(),
    Predecessor = nil,
    {ok, Successor} = connect(Id, Peer),
    Next = undefined,
    schedule_stabilize(),
    node(Id, Predecessor, Successor, Next, Store, Replica).

connect(Id, nil) ->
    Self = self(),
    Ref = monitor(Self),
    {ok, {Id, Ref, Self}};
connect(Id, Peer) ->
    Qref = make_ref(),
    Peer ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            Ref = monitor(Peer),
            {ok, {Skey, Ref, Peer}}
    after ?TIMEOUT ->
        io:format("Node ~p: Timeout while connecting to peer~n", [Id]),
        {error, timeout}
    end.

schedule_stabilize() ->
    timer:send_interval(?STABILIZE_INTERVAL, {stabilize}).

monitor(Pid) ->
    erlang:monitor(process, Pid).

drop(nil) ->
    ok;
drop(Ref) ->
    erlang:demonitor(Ref, [flush]).

node(Id, Predecessor, Successor, Next, Store, Replica) ->
    receive
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Next, Store, Replica);
        {notify, New} ->
            {NewPred, NewStore, NewReplica} = notify(New, Id, Predecessor, Store, Replica),
            node(Id, NewPred, Successor, Next, NewStore, NewReplica);
        {handover, Elements, Replicas} ->
            MergedStore = storage:merge(Elements, Store),
            MergedReplica = storage:merge(Replicas, Replica),
            node(Id, Predecessor, Successor, Next, MergedStore, MergedReplica);
        {request, Peer} ->
            request(Peer, Predecessor, Successor),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        {status, Pred, Nx} ->
            {NewSucc, NewNext} = stabilize(Pred, Nx, Id, Successor),
            node(Id, Predecessor, NewSucc, NewNext, Store, Replica);
        {stabilize} ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        {add, Key, Value, Qref, Client} ->
            NewStore = add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store, Replica),
            node(Id, Predecessor, Successor, Next, NewStore, Replica);
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, Id, Predecessor, Successor, Store, Replica),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        {replicate, Key, Value, Qref, From} ->
            NewReplica = storage:add(Key, Value, Replica),
            From ! {replicated, Qref},
            node(Id, Predecessor, Successor, Next, Store, NewReplica);
        {transfer_keys, NewId, NewPid} ->
            {EntriesToTransfer, ReplicasToTransfer, NewStore, NewReplica} =
                handle_transfer_keys(NewId, Id, Predecessor, Store, Replica),
            NewPid ! {keys_transferred, EntriesToTransfer, ReplicasToTransfer},
            node(Id, Predecessor, Successor, Next, NewStore, NewReplica);
        {keys_transferred, Entries, Replicas} ->
            MergedStore = storage:merge(Entries, Store),
            MergedReplica = storage:merge(Replicas, Replica),
            node(Id, Predecessor, Successor, Next, MergedStore, MergedReplica);
        {print_state} ->
            io:format(
                "Node ~p: State => Predecessor: ~p, Successor: ~p, Next: ~p, Store: ~p, Replica: ~p~n",
                [Id, Predecessor, Successor, Next, Store, Replica]
            ),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        {terminate} ->
            io:format("Node ~p: Terminating.~n", [Id]),
            ok;
        {'DOWN', Ref, process, _, _} ->
            {NewPred, NewSucc, NewNext, NewStore, NewReplica} =
                down(Ref, Predecessor, Successor, Next, Id, Store, Replica),
            node(Id, NewPred, NewSucc, NewNext, NewStore, NewReplica);
        {get_successor, Qref, From} ->
            From ! {Qref, Successor},
            node(Id, Predecessor, Successor, Next, Store, Replica);
        Other ->
            io:format("Node ~p: Received unknown message: ~p~n", [Id, Other]),
            node(Id, Predecessor, Successor, Next, Store, Replica)
    end.

notify({Nkey, Npid}, Id, Predecessor, Store, Replica) ->
    case Predecessor of
        nil ->
            drop(nil),
            Ref = monitor(Npid),
            {{Nkey, Ref, Npid}, Store, Replica};
        {Pkey, _, _} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    {_, OldRef, _} = Predecessor,
                    drop(OldRef),

                    Ref = monitor(Npid),
                    {{Nkey, Ref, Npid}, Store, Replica};
                false ->
                    {Predecessor, Store, Replica}
            end
    end.

stabilize({_, _, Spid}) ->
    Spid ! {request, self()}.

request(Peer, Predecessor, Successor) ->
    NextNode =
        case Successor of
            {_, _, Spid} when Spid == self() ->
                Successor;
            {_, _, Spid} ->
                Qref = make_ref(),
                Spid ! {get_successor, Qref, self()},
                receive
                    {Qref, SuccSucc} ->
                        SuccSucc
                after ?TIMEOUT ->
                    undefined
                end;
            _ ->
                undefined
        end,
    Peer ! {status, Predecessor, NextNode}.

stabilize(Pred, Nx, Id, Successor) ->
    {Skey, SRef, Spid} = Successor,
    case Pred of
        nil ->
            Spid ! {notify, {Id, self()}},

            NewNext =
                case Nx of
                    undefined -> Successor;
                    _ -> Nx
                end,
            {Successor, NewNext};
        {Id, _, _} ->
            {Successor, Nx};
        {Skey, _, _} ->
            Spid ! {notify, {Id, self()}},

            NewNext =
                case Nx of
                    undefined -> Successor;
                    _ -> Nx
                end,
            {Successor, NewNext};
        {Xkey, XRef, Xpid} ->
            case key:between(Xkey, Id, Skey) of
                true ->
                    {_, OldRef, _} = Successor,
                    drop(OldRef),

                    NewRef = monitor(Xpid),
                    NewSuccessor = {Xkey, NewRef, Xpid},

                    NewNext =
                        case Nx of
                            undefined -> Successor;
                            _ -> Nx
                        end,
                    {NewSuccessor, NewNext};
                false ->
                    Spid ! {notify, {Id, self()}},

                    NewNext =
                        case Nx of
                            undefined -> Successor;
                            _ -> Nx
                        end,
                    {Successor, NewNext}
            end
    end.

down(Ref, {Pkey, Ref, Ppid}, Successor, Next, Id, Store, Replica) ->
    io:format("Node ~p: Predecessor ~p has failed~n", [Id, Ppid]),

    NewStore = storage:merge(Replica, Store),

    NewReplica = storage:create(),
    {nil, Successor, Next, NewStore, NewReplica};
down(Ref, Predecessor, {Skey, Ref, Spid}, Next, Id, Store, Replica) ->
    io:format("Node ~p: Successor ~p has failed~n", [Id, Spid]),
    NewSuccessor =
        case Next of
            undefined ->
                RefSelf = monitor(self()),
                {Id, RefSelf, self()};
            {Nkey, _, Npid} ->
                NRef = monitor(Npid),
                {Nkey, NRef, Npid}
        end,

    {Predecessor, NewSuccessor, undefined, Store, Replica};
down(_Ref, Predecessor, Successor, Next, _Id, Store, Replica) ->
    {Predecessor, Successor, Next, Store, Replica}.

add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store, Replica) ->
    case is_responsible(Key, Id, Predecessor) of
        true ->
            NewStore = storage:add(Key, Value, Store),
            {_, _, Spid} = Successor,
            Spid ! {replicate, Key, Value, Qref, self()},
            receive
                {replicated, Qref} ->
                    Client ! {Qref, ok}
            after ?TIMEOUT ->
                io:format("Node ~p: Replication timed out for key ~p~n", [Id, Key]),
                Client ! {Qref, error}
            end,
            NewStore;
        false ->
            {_, _, Spid} = Successor,
            Spid ! {add, Key, Value, Qref, Client},
            Store
    end.

lookup(Key, Qref, Client, Id, Predecessor, Successor, Store, Replica) ->
    case is_responsible(Key, Id, Predecessor) of
        true ->
            Result = storage:lookup(Key, Store),
            Client ! {Qref, Result};
        false ->
            {_, _, Spid} = Successor,
            Spid ! {lookup, Key, Qref, Client}
    end.

is_responsible(Key, Id, Predecessor) ->
    case Predecessor of
        nil ->
            true;
        {Pkey, _, _} ->
            key:between(Key, Pkey, Id)
    end.

handle_transfer_keys(NewId, Id, Predecessor, Store, Replica) ->
    From =
        case Predecessor of
            nil -> Id;
            {Pkey, _, _} -> Pkey
        end,
    {EntriesToTransfer, NewStore} = storage:split(From, NewId, Store),
    {ReplicasToTransfer, NewReplica} = storage:split(From, NewId, Replica),
    {EntriesToTransfer, ReplicasToTransfer, NewStore, NewReplica}.
