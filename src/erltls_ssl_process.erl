-module(erltls_ssl_process).
-author("silviu.caragea").

-include("erltls.hrl").

-behaviour(gen_server).

-define(VERIFY_NONE, 16#10000).
-define(COMPRESSION_NONE, 16#100000).

-define(SERVER, ?MODULE).

-record(state, {
    tcp,
    tls_ref,
    owner_pid,
    owner_monitor_ref,
    tcp_monitor_ref,
    hk_completed = false,
    socket_ref
}).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([
    new/3,
    close/1,
    controlling_process/2,
    handshake/2,
    encode_data/2,
    decode_data/2,
    shutdown/1
]).

new(TcpSocket, TlsOptions, Role) ->
    case get_context(TlsOptions) of
        {ok, Context} ->
            case erltls_nif:ssl_new(Context, Role, get_ssl_flags(TlsOptions)) of
                {ok, TlsSock} ->
                    get_ssl_process(Role, TcpSocket, TlsSock);
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

close(Pid) ->
    call(Pid, close).

controlling_process(Pid, NewOwner) ->
    call(Pid, {controlling_process, self(), NewOwner}).

handshake(Pid, TcpSocket) ->
    call(Pid, {handshake, TcpSocket}).

encode_data(Pid, Data) ->
    call(Pid, {encode_data, Data}).

decode_data(Pid, Data) ->
    call(Pid, {decode_data, Data}).

shutdown(Pid) ->
    call(Pid, shutdown).

%internals for gen_server

init(#state{tcp = TcpSocket} = State) ->
    TcpMonitorRef = erlang:monitor(port, TcpSocket),
    OwnerMonitorRef = erlang:monitor(process, State#state.owner_pid),
    SocketRef = #tlssocket{tcp_sock = TcpSocket, ssl_pid = self()},
    {ok, State#state{owner_monitor_ref = OwnerMonitorRef, tcp_monitor_ref = TcpMonitorRef, socket_ref = SocketRef}}.

handle_call({handshake, TcpSocket}, _From, #state{tls_ref = TlsSock} = State) ->
    case State#state.hk_completed of
        true ->
            {reply, {error, <<"handshake already completed">>}, State};
        _ ->
            case do_handshake(TcpSocket, TlsSock) of
                ok ->
                    {reply, ok, State#state{hk_completed = true}};
                Error ->
                    {reply, Error, State}
            end
    end;

handle_call({encode_data, Data}, _From, #state{tls_ref = TlsSock} = State) ->
    {reply, do_encode(TlsSock, Data), State};

handle_call({decode_data, TlsData}, _From, #state{tls_ref = TlsSock} = State) ->
    {reply, do_decode(TlsSock, TlsData), State};

handle_call({controlling_process, SenderPid, NewOwner}, _From, State) ->
    #state{owner_pid = OwnerPid, owner_monitor_ref = OwnerMonitRef} = State,

    case SenderPid =:= OwnerPid of
        true ->
            case OwnerMonitRef of
                undefined ->
                    ok;
                _ ->
                    erlang:demonitor(OwnerMonitRef)
            end,
            NewOwnerRef = erlang:monitor(process, NewOwner),
            {reply, ok, State#state {owner_pid = NewOwner, owner_monitor_ref = NewOwnerRef}};
        _ ->
            {reply, {error, not_owner}, State}
    end;

handle_call(shutdown, _From, State) ->
    {reply, erltls_nif:ssl_shutdown(State#state.tls_ref), State};

handle_call(close, _From, State) ->
    {stop, normal, ok, State};

handle_call(Request, _From, State) ->
    ?ERROR_MSG("handle_call unknown request: ~p", [Request]),
    {noreply, State}.

handle_cast(Request, State) ->
    ?ERROR_MSG("handle_cast unknown request: ~p", [Request]),
    {noreply, State}.

handle_info({tcp, TcpSocket, Data}, #state{tcp = TcpSocket, tls_ref = TlsRef, owner_pid = Pid, socket_ref = SockRef} = State) ->
    Pid ! {ssl, SockRef, erltls_nif:ssl_feed_data(TlsRef, Data)},
    {noreply, State};

handle_info({tcp_closed, TcpSocket}, #state{tcp = TcpSocket, owner_pid = Pid, socket_ref = SockRef} = State) ->
    Pid ! {ssl_closed, SockRef},
    {stop, normal, State};

handle_info({tcp_error, TcpSocket, Reason}, #state{tcp = TcpSocket, owner_pid = Pid, socket_ref = SockRef} = State) ->
    Pid ! {ssl_error, SockRef, Reason},
    {noreply, State};

handle_info({tcp_passive, TcpSocket}, #state{tcp = TcpSocket, owner_pid = Pid, socket_ref = SockRef} = State) ->
    Pid ! {ssl_passive, SockRef},
    {noreply, State};

handle_info({'DOWN', MonitorRef, _, _, _}, State) ->
    #state{tcp = TcpSocket, tls_ref = TlsRef, owner_monitor_ref = OwnerMonitorRef, tcp_monitor_ref = TcpMonitorRef} = State,

    case MonitorRef of
        OwnerMonitorRef ->
            case erltls_nif:ssl_shutdown(TlsRef) of
                ok ->
                    ok;
                BytesWrite when is_binary(BytesWrite) ->
                    gen_tcp:send(TcpSocket, BytesWrite);
                Error ->
                    ?ERROR_MSG("shutdown unexpected error:~p", [Error])
            end,
            gen_tcp:close(TcpSocket),
            {stop, normal, State};
        TcpMonitorRef ->
            {stop, normal, State};
        _ ->
            {noreply, State}
    end;

handle_info(Request, State) ->
    ?ERROR_MSG("handle_info unknown request: ~p", [Request]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

call(Pid, Message) ->
    try
        gen_server:call(Pid, Message)
    catch
        exit:{noproc, _} ->
            {error, ssl_not_started};
        _: Exception ->
            {error, Exception}
    end.

start_link(TcpSocket, TlsSock, HkCompleted) ->
    State = #state{tcp = TcpSocket, tls_ref = TlsSock, owner_pid = self(), hk_completed = HkCompleted},
    case gen_server:start_link(?MODULE, State, []) of
        {ok, Pid} ->
            case gen_tcp:controlling_process(TcpSocket, Pid) of
                ok ->
                    {ok, #tlssocket{tcp_sock = TcpSocket, ssl_pid = Pid}};
                Error ->
                    close(Pid),
                    Error
            end;
        Error ->
            Error
    end.

%internal methods

get_verify(verify_none) ->
    ?VERIFY_NONE;
get_verify(_) ->
    0.

get_compression(compression_none) ->
    ?COMPRESSION_NONE;
get_compression(_) ->
    0.

get_ciphers(null) ->
    null;
get_ciphers(Ciphers) when is_list(Ciphers) ->
    string:join(Ciphers, ":").

get_ssl_flags(Options) ->
    VerifyType = get_verify(erltls_utils:lookup(verify, Options)),
    CompressionType = get_compression(erltls_utils:lookup(compression, Options)),
    VerifyType bor CompressionType.

get_context(TlsOptions) ->
    CertFile = erltls_utils:lookup(certfile, TlsOptions),
    DhFile = erltls_utils:lookup(dhfile, TlsOptions),
    CaFile = erltls_utils:lookup(cacerts, TlsOptions),
    Ciphers = get_ciphers(erltls_utils:lookup(ciphers, TlsOptions)),
    erltls_manager:get_ctx(CertFile, Ciphers, DhFile, CaFile).

get_ssl_process(?SSL_ROLE_SERVER, TcpSocket, TlsSock) ->
    start_link(TcpSocket, TlsSock, false);
get_ssl_process(?SSL_ROLE_CLIENT, TcpSocket, TlsSock) ->
    case inet:getopts(TcpSocket, [active]) of
        {ok, [{active, CurrentMode}]} ->
            change_active(TcpSocket, CurrentMode, false),
            case do_handshake(TcpSocket, TlsSock) of
                ok ->
                    change_active(TcpSocket, false, CurrentMode),
                    start_link(TcpSocket, TlsSock, true);
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

change_active(_TcpSocket, CurrentMode, NewMode) when CurrentMode =:= NewMode ->
    ok;
change_active(TcpSocket, _CurrentMode, NewMode) ->
    inet:setopts(TcpSocket, [{active, NewMode}]).

do_encode(TlsSock, RawData) ->
    case erltls_nif:ssl_send_data(TlsSock, RawData) of
        TlsData when is_binary(TlsData) ->
            {ok, TlsData};
        Error ->
            Error
    end.

do_decode(TlsSock, TlsData) ->
    case erltls_nif:ssl_feed_data(TlsSock, TlsData) of
        RawData when is_binary(RawData) ->
            {ok, RawData};
        Error ->
            Error
    end.

do_handshake(TcpSocket, TlsSock) ->
    case erltls_nif:ssl_handshake(TlsSock) of
        {ok, 1} ->
            send_pending(TcpSocket, TlsSock);
        {ok, 0} ->
            send_pending(TcpSocket, TlsSock),
            {error, <<"handshake failed">>};
        {error, ?SSL_ERROR_WANT_READ} ->
            case send_pending(TcpSocket, TlsSock) of
                ok ->
                    read_handshake(TcpSocket, TlsSock);
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

read_handshake(TcpSocket, TlsSock) ->
    case gen_tcp:recv(TcpSocket, 0) of
        {ok, Packet} ->
            case erltls_nif:ssl_feed_data(TlsSock, Packet) of
                ok ->
                    do_handshake(TcpSocket, TlsSock);
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

send_pending(TcpSocket, TlsSock) ->
    case erltls_nif:ssl_send_pending(TlsSock) of
        <<>> ->
            ok;
        Data ->
            gen_tcp:send(TcpSocket, Data)
    end.