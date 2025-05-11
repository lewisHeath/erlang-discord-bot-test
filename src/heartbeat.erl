-module(heartbeat).
-behaviour(gen_server).

%% API.
-export([start_link/0]).

%% gen_server.
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-export([
    send_heartbeat/0,
    send_heartbeat/1
]).

-record(state, {
    n,
    interval
}).

%% Macros.
-include("discord_api_types.hrl").

%% API.

send_heartbeat() ->
    gen_server:cast(?MODULE, heartbeat).

send_heartbeat(Interval) ->
    gen_server:call(?MODULE, {set_interval, Interval}),
    send_heartbeat().

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% gen_server.

init([]) ->
    {ok, #state{}}.

handle_call({set_interval, Interval}, _From, State) ->
    {reply, ok, State#state{interval = Interval}};
handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(heartbeat, State = #state{interval = Interval}) ->
    rate_limiter:send(#{?OP => ?HEARTBEAT, ?D => null}),
    N = rand:uniform(1000000), % New unique heartbeat
    erlang:send_after(Interval, self(), {heartbeat, N}),
    {noreply, State#state{n = N}};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({heartbeat, N}, State = #state{n = N, interval = Interval}) ->
    rate_limiter:send(#{?OP => ?HEARTBEAT, ?D => null}),
    erlang:send_after(Interval, self(), {heartbeat, N}),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
