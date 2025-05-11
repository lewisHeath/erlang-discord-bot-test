%% ==========================================================
%% The main module for handling the events sent from the
%% Discord gateway API
%% ==========================================================
-module(discord_api_gateway_handler).

%% ==========================================================
%% Includes
%% ==========================================================

-include("discord_api_types.hrl").
-include("macros.hrl").

%% ==========================================================
%% API
%% ==========================================================
-export([
    % handle_close/5,
    handle_gateway_event/5
]).

%% ==========================================================
%% Functions
%% ==========================================================
handle_gateway_event(?DISPATCH, D, _S, T, State) ->
    ?DEBUG("Handling DISPATCH T=~p D=~p", [T, D]),
    handle_dispatch(T, D, State);
handle_gateway_event(?HEARTBEAT, D, _S, T, State) ->
    ?DEBUG("Handling HEARTBEAT - d=~p t=~p", [D, T]),
    State;
handle_gateway_event(?RECONNECT, D, _S, T, State) ->
    ?DEBUG("Handling RECONNECT"),
    State;
handle_gateway_event(?INVALID_SESSION, D, _S, T, State) ->
    ?DEBUG("Handling INVALID_SESSION"),
    State;
handle_gateway_event(?HELLO, D, _S, T, State) ->
    ?DEBUG("Handling HELLO T=~p D=~p", [T, D]),
    #{heartbeat_interval := HeartbeatInterval} = D,
    ?DEBUG("Starting heartbeat with an interval of ~pms", [HeartbeatInterval]),
    heartbeat:send_heartbeat(HeartbeatInterval),
    Intents = intents:generate_intents_message(),
    ?DEBUG("USING IDENTIFY MSG: ~p", [Intents]),
    rate_limiter:send(Intents),
    State;
handle_gateway_event(?HEARTBEAT_ACK, D, _S, T, State) ->
    ?DEBUG("Handling HEARTBEAT_ACK"),
    State;
handle_gateway_event(UnknownOpcode, _, _S, _, State) ->
    ?WARNING("Unknown Opcode: ~p", [UnknownOpcode]),
    State.

% handle_close(_ConnPid, _StreamRef, CloseCode, Reason, State0) ->
%     ?DEBUG("Handling close code: ~p with reason: ~p", [CloseCode, Reason]),
%     CanReconnect = lists:member(CloseCode, ?RECONNECT_CLOSE_CODES),
%     State0#state{reconnect = CanReconnect}.

%% ==========================================================
%% Internal Functions
%% ==========================================================
handle_dispatch('RESUMED', _, State) ->
    ?DEBUG("Finished resuming the connection, setting state back to connected..."),
    State;
handle_dispatch('READY', D, State) ->
    ?DEBUG("READY D=~p", [D]),
    #{resume_gateway_url := ResumeGatewayUrl, session_id := SessionId} = D,
    ?DEBUG("Using resume_gateway_url: ~p and session_id: ~p", [ResumeGatewayUrl, SessionId]),
    State#state{resume_gateway_url = ResumeGatewayUrl, session_id = SessionId};
handle_dispatch(_, _, State) ->
    State.
