%% ======================================================
%% Record definitions
%% ======================================================
-record(status, {
    since = null,
    activities = [],
    status = <<"online">>,
    afk = false
}).

-record(state, {
    conn_pid,
    stream_ref,
    resume_gateway_url = "gateway.discord.gg",
    session_id,
    sequence_number = 0
}).

%% ======================================================
%% General
%% ======================================================
-define(BOT_TOKEN, config:get_value(bot_token)).
