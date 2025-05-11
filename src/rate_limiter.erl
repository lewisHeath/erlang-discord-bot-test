%% =================================================================================================================
%% All bots can make up to 50 requests per second to our API.
%% If no authorization header is provided, then the limit is applied to the IP address.
%% This is independent of any individual rate limit on a route.
%% If your bot gets big enough, based on its functionality, it may be impossible to stay below 50 requests per second during normal operations.
%% =================================================================================================================
-module(rate_limiter).
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
    send/1
]).

-record(state, {
    batch = []
}).
%% Macros.

-include("../include/discord_api_types.hrl").

%% API.

send(Binary) when is_binary(Binary) ->
    gen_server:cast(?MODULE, {send, Binary});
send(Term) ->
    Binary = term_to_binary(Term),
    gen_server:cast(?MODULE, {send, Binary}).

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% gen_server.

init([]) ->
    % 50 reqs per second is 1 per 20ms
    erlang:send_after(20, self(), dispatch),
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast({send, BinaryPayload}, State = #state{batch = Batch}) ->
    {noreply, State#state{batch = lists:append(Batch, [BinaryPayload])}};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(dispatch, State = #state{batch = [Msg | T]}) ->
    {ConnPid, StreamRef} = discord_ws_conn:get_ws(),
    ?DEBUG("Dispatching msg=~p", [binary_to_term(Msg)]),
    gun:ws_send(ConnPid, StreamRef, {binary, Msg}),
    erlang:send_after(20, self(), dispatch),
    {noreply, State#state{batch = T}};
handle_info(dispatch, State = #state{batch = []}) ->
    erlang:send_after(20, self(), dispatch),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
