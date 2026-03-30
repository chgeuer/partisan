%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Christopher Meiklejohn.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(partisan_acceptor_socket).
-author("Christopher Meiklejohn <christopher.meiklejohn@gmail.com>").

-behaviour(gen_server).

-include("partisan_logger.hrl").

%% public api

-export([start_link/1]).
-export([start_link/2]).
-export([start_link/3]).

%% gen_server api

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3,
         terminate/2]).

%% public api

%% Start with full listen_addr map (for custom transports that need extra config)
start_link(#{transport := _} = ListenAddr) ->
    gen_server:start_link(?MODULE, [ListenAddr], []).

start_link(PeerIP, PeerPort) ->
    start_link(PeerIP, PeerPort, gen_tcp).

start_link(PeerIP, PeerPort, Transport) ->
    gen_server:start_link(?MODULE, [PeerIP, PeerPort, Transport], []).

%% gen_server api

init([PeerIP, PeerPort, Transport]) when Transport =:= gen_tcp ->
    %% Standard TCP path — uses the acceptor pool as before
    AcceptorPoolSize = application:get_env(partisan, acceptor_pool_size, 10),
    _ = process_flag(trap_exit, true),
    Opts = [{active, once}, {mode, binary}, {ip, PeerIP}, {packet, 4},
            {reuseaddr, true}, {nodelay, true}, {keepalive, true}],
    case gen_tcp:listen(PeerPort, Opts) of
        {ok, Socket} ->
            ok = maybe_update_port_config(PeerIP, PeerPort, Socket),
            MRef = monitor(port, Socket),
            partisan_acceptor_pool:accept_socket(Socket, AcceptorPoolSize),
            {ok, {Socket, MRef, gen_tcp}};
        {error, Reason} ->
            {stop, Reason}
    end;

init([PeerIP, PeerPort, Transport]) ->
    %% Custom transport with IP+Port — level 1 listen/2 interface
    _ = process_flag(trap_exit, true),
    Opts = [{active, once}, {mode, binary}, {ip, PeerIP}, {packet, 4},
            {reuseaddr, true}, {nodelay, true}, {keepalive, true}],
    case Transport:listen(PeerPort, Opts) of
        {ok, Socket} ->
            ?LOG_INFO(#{
                description => "Partisan custom transport listening",
                transport => Transport,
                ip_address => PeerIP,
                port_number => PeerPort
            }),
            self() ! accept,
            {ok, {Socket, undefined, Transport}};
        {error, Reason} ->
            {stop, Reason}
    end;

init([#{transport := Transport} = ListenAddr]) ->
    %% Custom transport with full listen_addr — check for level 2 listen/1
    _ = process_flag(trap_exit, true),
    IP = maps:get(ip, ListenAddr, undefined),
    Port = maps:get(port, ListenAddr, 0),
    Result = case erlang:function_exported(Transport, listen, 1) of
        true ->
            Transport:listen(ListenAddr);
        false ->
            Opts = [{active, once}, {mode, binary}, {packet, 4},
                    {reuseaddr, true}, {nodelay, true}, {keepalive, true}
                    | case IP of
                        undefined -> [];
                        _ -> [{ip, IP}]
                      end],
            Transport:listen(Port, Opts)
    end,
    case Result of
        {ok, Socket} ->
            ?LOG_INFO(#{
                description => "Partisan custom transport listening (level 2)",
                transport => Transport,
                listen_addr => ListenAddr
            }),
            self() ! accept,
            {ok, {Socket, undefined, Transport}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(Req, _, State) ->
    {stop, {bad_call, Req}, State}.

handle_cast(Req, State) ->
    {stop, {bad_cast, Req}, State}.

handle_info(accept, {ListenSocket, _, Transport} = State) when Transport =/= gen_tcp ->
    %% Custom transport accept loop
    case Transport:accept(ListenSocket) of
        {ok, ClientSocket} ->
            WrappedSocket = partisan_peer_socket:accept(ClientSocket, Transport),
            try
                {ok, _Pid} = partisan_peer_service_server:start_custom(WrappedSocket),
                ?LOG_INFO(#{description => "Custom transport: connection accepted and server started"})
            catch
                Class:Reason:Stack ->
                    ?LOG_ERROR(#{description => "Custom transport: start_custom failed",
                                 class => Class, reason => Reason,
                                 stacktrace => Stack})
            end,
            self() ! accept,
            {noreply, State};
        {error, timeout} ->
            self() ! accept,
            {noreply, State};
        {error, Reason} ->
            ?LOG_WARNING(#{
                description => "Custom transport accept error",
                transport => Transport,
                reason => Reason
            }),
            erlang:send_after(100, self(), accept),
            {noreply, State}
    end;
handle_info({'DOWN', MRef, port, Socket, Reason}, {Socket, MRef, _Transport} = State) ->
    {stop, Reason, State};
handle_info({'DOWN', MRef, port, Socket, Reason}, {Socket, MRef} = State) ->
    {stop, Reason, State};
handle_info(_, State) ->
    {noreply, State}.

code_change(_, State, _) ->
    {ok, State}.

terminate(_, {Socket, _MRef, Transport}) ->
    _ = (catch Transport:close(Socket)),
    ok;
terminate(_, {Socket, _MRef}) ->
    _ = (catch gen_tcp:close(Socket)),
    ok.

%% private
maybe_update_port_config(PeerIP, 0, Socket) ->
    case inet:sockname(Socket) of
        {ok, {_IPAddress, Port}} ->
            ?LOG_INFO(#{
                description => "Partisan listening",
                ip_address => PeerIP,
                port_number => Port
            }),
            partisan_config:set(peer_port, Port),
            % search the listen addrs map for the provided ip Address
            % and update the port key
            ListenAddrs0 = partisan_config:get(listen_addrs),
            ListenAddrs = lists:map(fun(#{ip := IP} = Map) when PeerIP =:= IP ->
                                        maps:update(port, Port, Map);
                                       (Map) -> Map
                                    end, ListenAddrs0),
            partisan_config:set(listen_addrs, ListenAddrs),
            ok;
        _ -> ok
    end;
maybe_update_port_config(_, _, _) -> ok.
