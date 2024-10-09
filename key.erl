-module(key).
-export([generate/0, between/3]).

generate() ->
    random:uniform(1000000000).

between(Key, From, To) when From == To ->
    true;
between(Key, From, To) when From < To ->
    (Key > From) andalso (Key =< To);
between(Key, From, To) when From > To ->
    (Key > From) orelse (Key =< To).
