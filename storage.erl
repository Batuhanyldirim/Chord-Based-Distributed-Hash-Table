%%%-------------------------------------------------------------------
%%% @doc
%%% Simple storage module for key-value pairs.
%%%-------------------------------------------------------------------

-module(storage).
-export([create/0, add/3, lookup/2, merge/2, split/3, to_list/1]).

%%%-------------------------------------------------------------------
%%% API Functions
%%%-------------------------------------------------------------------

%% Create a new storage
create() ->
    [].

%% Add a key-value pair to the storage
add(Key, Value, Store) ->
    lists:keystore(Key, 1, Store, {Key, Value}).

%% Lookup a value by key in the storage
lookup(Key, Store) ->
    case lists:keyfind(Key, 1, Store) of
        false -> false;
        {Key, Value} -> {Key, Value}
    end.

%% Merge two storages
merge(Store1, Store2) ->
    lists:foldl(
        fun({Key, Value}, Acc) ->
            lists:keystore(Key, 1, Acc, {Key, Value})
        end,
        Store2,
        Store1
    ).

%% Split the storage based on key range
split(FromKey, ToKey, Store) ->
    {EntriesToTransfer, RemainingStore} = lists:partition(
        fun({Key, _Value}) ->
            key:between(Key, FromKey, ToKey)
        end,
        Store
    ),
    {EntriesToTransfer, RemainingStore}.

%% Convert storage to list of key-value pairs
to_list(Store) ->
    Store.
