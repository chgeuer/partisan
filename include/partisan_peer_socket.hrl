% Guard helpers for matching TCP, SSL/TLS, and custom transport messages
% in active mode. Custom transports may emit messages tagged with either
% `tcp' (backward-compatible) or `partisan_transport' (preferred for new
% transports).
-define(DATA_MSG(Tag), Tag == tcp orelse Tag == ssl orelse Tag == partisan_transport).
-define(ERROR_MSG(Tag), Tag == tcp_error orelse Tag == ssl_error orelse Tag == partisan_transport_error).
-define(CLOSED_MSG(Tag), Tag == tcp_closed orelse Tag == ssl_closed orelse Tag == partisan_transport_closed).

-record(ping, {
    from                    ::  node(),
    id                      ::  partisan:reference(),
    timestamp               ::  non_neg_integer()
}).

-record(pong, {
    from                    ::  node(),
    id                      ::  partisan:reference(),
    timestamp               ::  non_neg_integer()
}).