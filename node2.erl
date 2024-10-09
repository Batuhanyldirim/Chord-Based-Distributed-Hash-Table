-module(node2).
-export([start/1, start/2, init/2, node/4]).
-define(STABILIZE_INTERVAL, 1000).
-define(TIMEOUT, 10000).

start(Id) ->
    start(Id, nil).

start(Id, Peer) ->
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    Predecessor = nil,
    {ok, Successor} = connect(Id, Peer),
    schedule_stabilize(),
    Store = storage:create(),
    node(Id, Predecessor, Successor, Store).

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

schedule_stabilize() ->
    timer:send_interval(?STABILIZE_INTERVAL, {stabilize}).

node(Id, Predecessor, Successor, Store) ->
    receive
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Store);
        {notify, New} ->
            {NewPred, NewStore} = notify(New, Id, Predecessor, Store),
            node(Id, NewPred, Successor, NewStore);
        {handover, Elements} ->
            MergedStore = storage:merge(Elements, Store),
            node(Id, Predecessor, Successor, MergedStore);
        {request, Peer} ->
            request(Peer, Predecessor),
            node(Id, Predecessor, Successor, Store);
        {status, Pred} ->
            {Succ, NewStore} = stabilize(Pred, Id, Successor, Store),
            node(Id, Predecessor, Succ, NewStore);
        {stabilize} ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Store);
        {add, Key, Value, Qref, Client} ->
            NewStore = add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, NewStore);
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Store);
        {transfer_keys, NewId, NewPid} ->
            {EntriesToTransfer, NewStore} = handle_transfer_keys(NewId, Id, Predecessor, Store),
            NewPid ! {keys_transferred, EntriesToTransfer},
            node(Id, Predecessor, Successor, NewStore);
        {keys_transferred, Entries} ->
            NewStore = storage:merge(Entries, Store),
            node(Id, Predecessor, Successor, NewStore);
        {print_state} ->
            io:format(
                "Node ~p: State => Predecessor: ~p, Successor: ~p, Store: ~p~n",
                [Id, Predecessor, Successor, Store]
            ),
            node(Id, Predecessor, Successor, Store);
        {terminate} ->
            io:format("Node ~p: Terminating.~n", [Id]),
            ok;
        Other ->
            io:format("Node ~p: Received unknown message: ~p~n", [Id, Other]),
            node(Id, Predecessor, Successor, Store)
    end.

notify({Nkey, Npid}, Id, Predecessor, Store) ->
    case Predecessor of
        nil ->
            {NewPred, NewStore} = handle_new_predecessor(nil, Nkey, Npid, Id, Store),
            {NewPred, NewStore};
        {Pkey, Ppid} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    {NewPred, NewStore} = handle_new_predecessor(
                        Predecessor, Nkey, Npid, Id, Store
                    ),
                    {NewPred, NewStore};
                false ->
                    {Predecessor, Store}
            end
    end.

handle_new_predecessor(Predecessor, Nkey, Npid, Id, Store) ->
    From =
        case Predecessor of
            nil -> Id;
            {Pkey, _Ppid} -> Pkey
        end,
    {KeysToHandOver, KeysToKeep} = storage:split(From, Nkey, Store),
    Npid ! {handover, KeysToHandOver},
    {{Nkey, Npid}, KeysToKeep}.

stabilize(Successor) ->
    {_, Spid} = Successor,
    Spid ! {request, self()}.

stabilize(Pred, Id, Successor, Store) ->
    {Skey, Spid} = Successor,
    case Pred of
        nil ->
            Spid ! {notify, {Id, self()}},
            {Successor, Store};
        {Id, _} ->
            {Successor, Store};
        {Skey, _} ->
            Spid ! {notify, {Id, self()}},
            {Successor, Store};
        {Xkey, Xpid} ->
            case key:between(Xkey, Id, Skey) of
                true ->
                    NewSuccessor = {Xkey, Xpid},

                    {_, NewSpid} = NewSuccessor,
                    NewSpid ! {transfer_keys, Id, self()},
                    {NewSuccessor, Store};
                false ->
                    Spid ! {notify, {Id, self()}},
                    {Successor, Store}
            end
    end.

request(Peer, Predecessor) ->
    Peer ! {status, Predecessor}.

add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store) ->
    case is_responsible(Key, Id, Predecessor) of
        true ->
            NewStore = storage:add(Key, Value, Store),
            Client ! {Qref, ok},
            NewStore;
        false ->
            {_, Spid} = Successor,
            Spid ! {add, Key, Value, Qref, Client},
            Store
    end.

lookup(Key, Qref, Client, Id, Predecessor, Successor, Store) ->
    case is_responsible(Key, Id, Predecessor) of
        true ->
            Result = storage:lookup(Key, Store),
            Client ! {Qref, Result};
        false ->
            {_, Spid} = Successor,
            Spid ! {lookup, Key, Qref, Client}
    end.

is_responsible(Key, Id, Predecessor) ->
    case Predecessor of
        nil ->
            true;
        {Pkey, _Ppid} ->
            key:between(Key, Pkey, Id)
    end.

handle_transfer_keys(NewId, Id, Predecessor, Store) ->
    From =
        case Predecessor of
            nil -> Id;
            {Pkey, _Ppid} -> Pkey
        end,
    {EntriesToTransfer, NewStore} = storage:split(From, NewId, Store),
    {EntriesToTransfer, NewStore}.
