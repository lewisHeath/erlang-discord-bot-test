-module(discord_api_gen_server).

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

%% Macros

-define(GATEWAY_URL, "gateway.discord.gg").
-define(BOT_TOKEN, config:get_value(bot_token)).

-include("../include/discord_api_types.hrl").
-include("../include/macros.hrl").

%% API.

-spec start_link() -> {ok, pid()}.
start_link() ->
    ?DEBUG("Starting the discord api!", []),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% gen_server.

init([]) ->
    {ok, BotToken} = application:get_env(bot_token),
    ?DEBUG("Using bot token: ~p", [BotToken]),
    self() ! setup_connection,
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast({send, BinaryPayload}, State = #state{conn_pid = ConnPid, stream_ref = StreamRef}) when is_binary(BinaryPayload) ->
    ?DEBUG("Sending binary payload ~p to the discord api", [BinaryPayload]),
    gun:ws_send(ConnPid, StreamRef, {binary, BinaryPayload}),
    {noreply, State};
handle_cast({send, Payload}, State = #state{conn_pid = ConnPid, stream_ref = StreamRef}) ->
    ?DEBUG("Sending payload ~p to the discord api", [Payload]),
    BinaryPayload = term_to_binary(Payload),
    gun:ws_send(ConnPid, StreamRef, {binary, BinaryPayload}),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(setup_connection, State) ->
    % Open the connection to the gateway
    {ok, ConnPid} = gun:open(?GATEWAY_URL, 443,
                            #{protocols => [http],
                              retry => 0,
                              transport => tls,
                              tls_opts => [{verify, verify_none}, {cacerts, certifi:cacerts()}],
                              http_opts => #{version => 'HTTP/1.1'}}),
    % Await the successfull connection
    {ok, http} = gun:await_up(ConnPid),
    % Upgrade to a websocket
    gun:ws_upgrade(ConnPid, "/?v=10&encoding=etf"),
    {noreply, State};
handle_info(reconnect, State = #state{conn_pid = ConnPid, stream_ref = StreamRef}) ->
    % TODO: make sure old connection is closed with an opcode that is not 1000 or 1001
    ?DEBUG("Reconnecting to the discord api..."),
    gun:ws_send(ConnPid, StreamRef, close),
    NewState = reconnect(State),
    self() ! heartbeat,
    {noreply, NewState};
handle_info({gun_upgrade, ConnPid, StreamRef, [<<"websocket">>], _Headers}, State) ->
    ?DEBUG("Got a gun_upgrade..."),
    {noreply, State#state{conn_pid = ConnPid, stream_ref = StreamRef}};
% This handles the initial message from discord when we have not completed the handshake yet
handle_info({gun_ws, ConnPid, StreamRef, {binary, Data}}, State = #state{handshake_status = not_connected}) ->
    NewState = establish_discord_connection(ConnPid, StreamRef, Data, State),
    {noreply, NewState};
handle_info({gun_ws, ConnPid, StreamRef, {close, CloseCode, Reason}}, State) ->
    % Handle a disconnect from the discord gateway
    NewState = discord_api_gateway_handler:handle_close(ConnPid, StreamRef, CloseCode, Reason, State),
    {noreply, NewState};
handle_info({gun_ws, ConnPid, StreamRef, close}, State) ->
    ?DEBUG("Received a close code of nothing, trying to reconnect"),
    self() ! reconnect,
    {noreply, State};
% This is the main handler for when a gateway payload is sent to the application
handle_info({gun_ws, _ConnPid, _StreamRef, {binary, BinaryData}}, State = #state{sequence_number = SequenceNumber}) ->
    #{s := S, op := OP, d := D, t := T} = binary_to_term(BinaryData),
    NewSequenceNumber =
        case S of
            nil ->
                SequenceNumber;
            Number -> %% TODO handle missing sequence numbers
                Number
        end,
    discord_api_gateway_handler:handle_binary(OP, D, T),
    {noreply, State#state{sequence_number = NewSequenceNumber}};
handle_info({gun_ws, _ConnPid, _StreamRef, {text, TextData}}, State = #state{}) ->
    ?WARNING("Received text data: ~p", [TextData]),
    {noreply, State#state{}};
% This is when we can reconnect, which is decided when we process the close code sent to us, false by default
handle_info({gun_down, ConnPid, Protocol, Reason, KilledStreams}, State = #state{reconnect = true, resume_gateway_url = ResumeGatewayUrl, sequence_number = SequenceNumber, session_id = SessionId}) ->
    ?DEBUG("Got a gun_down message with protocol: ~p, reason: ~p, killed streams: ~p", [Protocol, Reason, KilledStreams]),
    ?DEBUG("Attempting to reconnect to url: ~p with session ID: ~p and sequence number: ~p", [ResumeGatewayUrl, SessionId, SequenceNumber]),
    % Flush the messages from the connection Pid
    gun:flush(ConnPid),
    self() ! reconnect,
    {noreply, State#state{reconnect = false}};
% If we cannot re-connect then send a setup_connection message to ourselves to re-connect to the original URL
handle_info({gun_down, ConnPid, Protocol, Reason, KilledStreams}, State) ->
    ?DEBUG("Got a gun_down message with connection pid: ~p protocol: ~p, reason: ~p, killed streams: ~p", [ConnPid, Protocol, Reason, KilledStreams]),
    % Flush the messages from the connection Pid
    gun:flush(ConnPid),
    self() ! reconnect, % maybe
    {noreply, State};
handle_info(heartbeat, State=#state{conn_pid = ConnPid, stream_ref = StreamRef, heartbeat_interval = HeartbeatInterval}) ->
    gun:ws_send(ConnPid, StreamRef, {binary, term_to_binary(#{ ?OP => 1, ?D => null })}),
    erlang:send_after(HeartbeatInterval, self(), heartbeat),
    {noreply, State};
handle_info(Info, State) ->
    ?DEBUG("Handle info: ~p", [Info]),
    ?DEBUG("With State: ~p", [State]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% ===================================================================
%% Internal functions
%% ===================================================================
establish_discord_connection(ConnPid, StreamRef, Data, State) ->
    % Complete handshake with Discord
    % Decode the frame, which should be the initial handshake message
    DecodedData = binary_to_term(Data),
    ?DEBUG("Initial Handshake Data: ~p", [DecodedData]),
    % Make sure the OP is 10 and save the heartbeat interval
    #{op := 10, d := #{heartbeat_interval := HeartbeatInterval}} = DecodedData,
    ?DEBUG("Starting heartbeat with an interval of ~pms", [HeartbeatInterval]),
    erlang:send_after(HeartbeatInterval, self(), heartbeat),
    % Send the identify with intents message
    gun:ws_send(ConnPid, StreamRef, {binary, term_to_binary(generate_intents_message())}),
    ?DEBUG("USING IDENTIFY MSG: ~p", [generate_intents_message()]),
    % Wait for the READY message and the GUILD_CREATE message(s)
    receive
        {gun_ws, ConnPid, StreamRef, {binary, Ready}} ->
            {ResumeGatewayUrl, SessionId} = get_data_from_ready_message(binary_to_term(Ready))
    end,
    % status_handler:update_status(#status{activities = [#{
    %     <<"name">> => <<"name">>,
    %     <<"state">> => <<"Lonely bot...">>,
    %     <<"type">> => 4
    % }], status = <<"idle">>}),
    State#state{
        heartbeat_interval = HeartbeatInterval,
        handshake_status = connected,
        resume_gateway_url = ResumeGatewayUrl,
        session_id = SessionId,
        sequence_number = 1
    }.

reconnect(State = #state{resume_gateway_url = ResumeGatewayUrl, session_id = SessionID, sequence_number = SequenceNumber}) ->
    % Open the connection to the resume url gateway
    {ok, ConnPid} = gun:open(ResumeGatewayUrl, 443,
                            #{protocols => [http],
                              retry => 0,
                              transport => tls,
                              tls_opts => [{verify, verify_none}, {cacerts, certifi:cacerts()}],
                              http_opts => #{version => 'HTTP/1.1'}}),
    % Await the successfull connection
    {ok, http} = gun:await_up(ConnPid),
    % Upgrade to a websocket
    gun:ws_upgrade(ConnPid, "/?v=10&encoding=etf"),
    receive
        {gun_upgrade, ConnPid, StreamRef, [<<"websocket">>], _Headers} ->
            % Ready to send the resume code (6)
            ResumeMessage =
                #{
                    ?OP => 6,
                    ?D => #{
                        <<"token">> => list_to_binary(?BOT_TOKEN),
                        <<"session_id">> => SessionID,
                        <<"seq">> => SequenceNumber
                    }
                },
            gun:ws_send(ConnPid, StreamRef, {binary, term_to_binary(ResumeMessage)})
    end,
    ?DEBUG("Sent the resume message: ~p to the new ws url: ~p", [ResumeMessage, ResumeGatewayUrl]),
    State#state{handshake_status = connected, conn_pid = ConnPid, stream_ref = StreamRef}.

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

generate_intents() ->
    config:get_value(intents).

get_data_from_ready_message(ReadyMessage) ->
    ?DEBUG("ready data: ~p", [ReadyMessage]),
    D = maps:get(d, ReadyMessage, #{}),
    ResumeGatewayUrl = maps:get(resume_gateway_url, D),
    SessionId = maps:get(session_id, D),
    ?DEBUG("Using resume_gateway_url: ~p and session_id: ~p", [ResumeGatewayUrl, SessionId]),
    {binary_to_list(binary:replace(ResumeGatewayUrl, <<"wss://">>, <<"">>)), SessionId}.
