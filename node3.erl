-module(node3).
-export([start/1, start/2, init/2, node/5]).
-define(STABILIZE_INTERVAL, 1000).
-define(TIMEOUT, 10000).

start(Id) ->
    start(Id, nil).

start(Id, Peer) ->
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    Store = storage:create(),
    Predecessor = nil,
    {ok, Successor} = connect(Id, Peer),
    Next = undefined,
    schedule_stabilize(),
    node(Id, Predecessor, Successor, Next, Store).

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

node(Id, Predecessor, Successor, Next, Store) ->
    receive
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Next, Store);
        {notify, New} ->
            {NewPred, NewStore} = notify(New, Id, Predecessor, Store),
            node(Id, NewPred, Successor, Next, NewStore);
        {handover, Elements} ->
            MergedStore = storage:merge(Elements, Store),
            node(Id, Predecessor, Successor, Next, MergedStore);
        {request, Peer} ->
            request(Peer, Predecessor, Successor),
            node(Id, Predecessor, Successor, Next, Store);
        {status, Pred, Nx} ->
            {NewSucc, NewNext} = stabilize(Pred, Nx, Id, Successor),
            node(Id, Predecessor, NewSucc, NewNext, Store);
        {stabilize} ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Next, Store);
        {add, Key, Value, Qref, Client} ->
            NewStore = add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Next, NewStore);
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Next, Store);
        {transfer_keys, NewId, NewPid} ->
            {EntriesToTransfer, NewStore} = handle_transfer_keys(NewId, Id, Predecessor, Store),
            NewPid ! {keys_transferred, EntriesToTransfer},
            node(Id, Predecessor, Successor, Next, NewStore);
        {keys_transferred, Entries} ->
            NewStore = storage:merge(Entries, Store),
            node(Id, Predecessor, Successor, Next, NewStore);
        {print_state} ->
            io:format(
                "Node ~p: State => Predecessor: ~p, Successor: ~p, Next: ~p, Store: ~p~n",
                [Id, Predecessor, Successor, Next, Store]
            ),
            node(Id, Predecessor, Successor, Next, Store);
        {terminate} ->
            io:format("Node ~p: Terminating.~n", [Id]),
            ok;
        {'DOWN', Ref, process, _, _} ->
            {NewPred, NewSucc, NewNext} = down(Ref, Predecessor, Successor, Next, Id),
            node(Id, NewPred, NewSucc, NewNext, Store);
        {get_successor, Qref, From} ->
            From ! {Qref, Successor},
            node(Id, Predecessor, Successor, Next, Store);
        Other ->
            node(Id, Predecessor, Successor, Next, Store)
    end.

notify({Nkey, Npid}, Id, Predecessor, Store) ->
    case Predecessor of
        nil ->
            drop(nil),

            Ref = monitor(Npid),
            {{Nkey, Ref, Npid}, Store};
        {Pkey, _, _} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    {_, OldRef, _} = Predecessor,
                    drop(OldRef),

                    Ref = monitor(Npid),
                    {{Nkey, Ref, Npid}, Store};
                false ->
                    {Predecessor, Store}
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

down(Ref, {Pkey, Ref, Ppid}, Successor, Next, Id) ->
    io:format("Node ~p: Predecessor ~p has failed~n", [Id, Ppid]),
    {nil, Successor, Next};
down(Ref, Predecessor, {Skey, Ref, Spid}, Next, Id) ->
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

    {Predecessor, NewSuccessor, undefined};
down(_Ref, Predecessor, Successor, Next, _Id) ->
    {Predecessor, Successor, Next}.

add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store) ->
    case is_responsible(Key, Id, Predecessor) of
        true ->
            NewStore = storage:add(Key, Value, Store),
            Client ! {Qref, ok},
            NewStore;
        false ->
            {_, _, Spid} = Successor,
            Spid ! {add, Key, Value, Qref, Client},
            Store
    end.

lookup(Key, Qref, Client, Id, Predecessor, Successor, Store) ->
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

handle_transfer_keys(NewId, Id, Predecessor, Store) ->
    From =
        case Predecessor of
            nil -> Id;
            {Pkey, _, _} -> Pkey
        end,
    {EntriesToTransfer, NewStore} = storage:split(From, NewId, Store),
    {EntriesToTransfer, NewStore}.
