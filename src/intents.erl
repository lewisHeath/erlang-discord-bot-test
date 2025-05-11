-module(intents).
-export([
    generate_intents_message/0
]).

-include("discord_api_types.hrl").
-include("macros.hrl").

generate_intents_message() ->
    #{
        ?OP => 2,
        ?D => #{
            <<"token">> => list_to_binary(?BOT_TOKEN),
            <<"properties">> => #{
                <<"os">> => <<"linux">>,
                <<"browser">> => <<"discord_api_erlang_libary">>,
                <<"device">> => <<"discord_api_erlang_libary">>
            },
            <<"intents">> => generate_intents()
        }
    }.

%% ======================================================
%% Internal Functions
%% ======================================================
% TODO: make this better in the future
generate_intents() ->
    config:get_value(intents).
