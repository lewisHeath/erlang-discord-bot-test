-module(status_handler).

-export([update_status/1]).

-include("discord_api_types.hrl").
-include("macros.hrl").

update_status(#status{since = Since, activities = Activities, status = Status, afk = Afk}) ->
    Payload = #{
        <<"op">> => 3,
        <<"d">> => #{
            <<"since">> => Since,
            <<"activities">> => Activities,
            <<"status">> => Status,
            <<"afk">> => Afk
        }
    },
    ?DEBUG("Generated status update payload: ~p~n", [Payload]),
    rate_limiter:send(Payload).
