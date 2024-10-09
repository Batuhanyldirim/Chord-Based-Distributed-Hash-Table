-module(test).

-compile(export_all).

-define(Timeout, 1000).

start(Module) ->
    Id = key:generate(),
    apply(Module, start, [Id]).

start(Module, P) ->
    Id = key:generate(),
    apply(Module, start, [Id, P]).

start(_, 0, _) ->
    ok;
start(Module, N, P) ->
    start(Module, P),
    start(Module, N - 1, P).

add(Key, Value, P) ->
    Q = make_ref(),
    P ! {add, Key, Value, Q, self()},
    receive
        {Q, ok} ->
            ok
    after ?Timeout ->
        {error, "timeout"}
    end.

lookup(Key, Node) ->
    Q = make_ref(),
    Node ! {lookup, Key, Q, self()},
    receive
        {Q, Value} ->
            Value
    after ?Timeout ->
        {error, "timeout"}
    end.

keys(N) ->
    lists:map(fun(_) -> key:generate() end, lists:seq(1, N)).

add(Keys, P) ->
    lists:foreach(fun(K) -> add(K, gurka, P) end, Keys).

check(Keys, P) ->
    T1 = now(),
    {Failed, Timeout} = check(Keys, P, 0, 0),
    T2 = now(),
    Done = (timer:now_diff(T2, T1) div 1000),
    io:format("~w lookup operation in ~w ms ~n", [length(Keys), Done]),
    io:format("~w lookups failed, ~w caused a timeout ~n", [Failed, Timeout]).

check([], _, Failed, Timeout) ->
    {Failed, Timeout};
check([Key | Keys], P, Failed, Timeout) ->
    case lookup(Key, P) of
        {Key, _} ->
            check(Keys, P, Failed, Timeout);
        {error, _} ->
            check(Keys, P, Failed, Timeout + 1);
        false ->
            check(Keys, P, Failed + 1, Timeout)
    end.

% FOR NODE1
% erl -name chord_node1@192.168.0.214 -setcookie mycookie
% Id1 = 1000.
% Pid1 = node4:start(Id1).
% register(node, Pid1).


% Qref = make_ref().
% Pid1 ! {add, 12345, "Value1", Qref, self()}.


% FOR NODE2
% erl -name chord_node2@192.168.0.214 -setcookie mycookie
% net_adm:ping('chord_node1@192.168.0.214').
% nodes().
% Pid1 = rpc:call('chord_node1@192.168.0.214', erlang, whereis, [node]).
% Id2 = 2000.
% Pid2 = node4:start(Id2, Pid1).


% FOR NODE3
% erl -name chord_node3@192.168.0.214 -setcookie mycookie
% net_adm:ping('chord_node1@192.168.0.214').
% Pid1 = rpc:call('chord_node1@192.168.0.214', erlang, whereis, [node]).
% Id3 = 3000.
% Pid3 = node4:start(Id3, Pid1).
% nodes().


% Qref = make_ref().
% Pid3 ! {lookup, 12345, Qref, self()}.
