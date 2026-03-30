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

-module(partisan_acceptor_socket_pool_sup).
-behaviour(supervisor).

-author("Christopher Meiklejohn <christopher.meiklejohn@gmail.com>").

-include("partisan_logger.hrl").

%% API
-export([start_link/0]).

%% Supervisor Callbacks
-export([init/1]).



%% =============================================================================
%% API
%% =============================================================================



start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).



%% =============================================================================
%% SUPERVISOR CALLBACKS
%% =============================================================================



init([]) ->
    Flags = #{strategy => rest_for_one},
    Pool = pool(),
    ListenAddrs = partisan_config:listen_addrs(),

    ?LOG_INFO(#{
        description => "Starting Partisan listener",
        listen_addrs => ListenAddrs
    }),

    Sockets = [
        socket(ListenAddr) || ListenAddr <- ListenAddrs
    ],

    {ok, {Flags, lists:flatten([Pool, Sockets])}}.



%% =============================================================================
%% PRIVATE
%% =============================================================================


%% @private
%% Custom transport with full listen_addr — use start_link/1 so transport
%% can access all address fields (namespace, auth, hybrid_connection, etc.)
socket(#{transport := Transport} = ListenAddr) when Transport =/= gen_tcp ->
    IP = maps:get(ip, ListenAddr, Transport),
    Port = maps:get(port, ListenAddr, 0),
    #{
        id => {partisan_acceptor_socket, IP, Port},
        start => {partisan_acceptor_socket, start_link, [ListenAddr]}
    };
socket(#{ip := IP, port := Port, transport := Transport}) ->
    #{
        id => {partisan_acceptor_socket, IP, Port},
        start => {partisan_acceptor_socket, start_link, [IP, Port, Transport]}
    };
socket(#{ip := IP, port := Port}) ->
    #{
        id => {partisan_acceptor_socket, IP, Port},
        start => {partisan_acceptor_socket, start_link, [IP, Port]}
    }.

%% @private
pool() ->
    #{
        id => partisan_acceptor_pool,
        start => {partisan_acceptor_pool, start_link, []}
    }.
