-module(discord_api_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Procs = [
        #{
            id => discord_ws_conn,
            start => {discord_ws_conn, start_link, []},
            restart => permanent,
            type => worker,
            modules => [discord_ws_conn]
        },
        #{
            id => heartbeat,
            start => {heartbeat, start_link, []},
            restart => permanent,
            type => worker,
            modules => [heartbeat]
        },
        #{
            id => rate_limiter,
            start => {rate_limiter, start_link, []},
            restart => permanent,
            type => worker,
            modules => [rate_limiter]
        }
    ],
    {ok, {{one_for_one, 1, 5}, Procs}}.
