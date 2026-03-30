%% -------------------------------------------------------------------
%%
%% Copyright (c) 2026 Christian Geuer-Pollmann.  All Rights Reserved.
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

%% -----------------------------------------------------------------------------
%% @doc Behaviour for pluggable Partisan transports.
%%
%% Transports can implement two interface levels:
%%
%% <b>Level 1 (legacy, gen_tcp-compatible)</b>: Required callbacks that mirror
%% the gen_tcp API. Suitable for transports where IP + port fully identifies
%% the endpoint (e.g., vsock, Unix domain sockets).
%%
%% <b>Level 2 (rich)</b>: Optional callbacks that receive the full
%% `listen_addr' map. Suitable for transports that need additional
%% configuration beyond IP + port (e.g., Azure Relay needs namespace,
%% hybrid connection name, and auth credentials).
%%
%% Partisan checks for level 2 callbacks first and falls back to level 1.
%%
%% == Active Mode Messages ==
%%
%% When `{active, once}' is set via `setopts/2', the transport must deliver
%% the next received message to the socket owner as one of:
%%
%% <ul>
%%   <li>`{tcp, Socket, Data}' — backward-compatible, works with existing code</li>
%%   <li>`{partisan_transport, Socket, Data}' — preferred for new transports</li>
%% </ul>
%%
%% Likewise for errors and close:
%% <ul>
%%   <li>`{tcp_error, Socket, Reason}' or `{partisan_transport_error, Socket, Reason}'</li>
%%   <li>`{tcp_closed, Socket}' or `{partisan_transport_closed, Socket}'</li>
%% </ul>
%% @end
%% -----------------------------------------------------------------------------
-module(partisan_transport).

%% =============================================================================
%% Level 1 callbacks — gen_tcp-compatible interface (required)
%% =============================================================================

-callback listen(
    Port :: inet:port_number(),
    Opts :: [gen_tcp:listen_option()]
) -> {ok, ListenSocket :: term()} | {error, Reason :: term()}.

-callback accept(
    ListenSocket :: term()
) -> {ok, Socket :: term()} | {error, Reason :: term()}.

-callback connect(
    Address :: inet:socket_address() | inet:hostname() | term(),
    Port :: inet:port_number(),
    Opts :: [gen_tcp:connect_option()],
    Timeout :: timeout()
) -> {ok, Socket :: term()} | {error, Reason :: term()}.

-callback send(
    Socket :: term(),
    Data :: iodata()
) -> ok | {error, Reason :: term()}.

-callback recv(
    Socket :: term(),
    Length :: non_neg_integer(),
    Timeout :: timeout()
) -> {ok, binary()} | {error, Reason :: term()}.

-callback close(
    Socket :: term()
) -> ok.

-callback setopts(
    Socket :: term(),
    Opts :: [term()]
) -> ok | {error, Reason :: term()}.

-callback controlling_process(
    Socket :: term(),
    Pid :: pid()
) -> ok | {error, Reason :: term()}.


%% =============================================================================
%% Level 2 callbacks — rich interface with full listen_addr (optional)
%% =============================================================================

%% @doc Start listening using the full listen_addr map.
%% The map contains transport-specific configuration (namespace, auth, etc.).
-callback listen(
    ListenAddr :: partisan:listen_addr()
) -> {ok, ListenSocket :: term()} | {error, Reason :: term()}.

%% @doc Connect to a remote endpoint using the full listen_addr map.
%% The map contains the remote endpoint's transport-specific address.
-callback connect(
    ListenAddr :: partisan:listen_addr(),
    Timeout :: timeout()
) -> {ok, Socket :: term()} | {error, Reason :: term()}.

-optional_callbacks([
    {listen, 1},
    {connect, 2}
]).
