#!/usr/bin/lua
-- uhttpd CGI entry; PATH_INFO selects one fixed route in gateway.lua.
dofile("/usr/lib/ilink/gateway.lua")
handle_request({
    PATH_INFO = os.getenv("PATH_INFO") or os.getenv("SCRIPT_NAME"),
    REQUEST_METHOD = os.getenv("REQUEST_METHOD"),
    HTTP_AUTHORIZATION = os.getenv("HTTP_AUTHORIZATION"),
    QUERY_STRING = os.getenv("QUERY_STRING") or "",
    HTTP_RANGE = os.getenv("HTTP_RANGE") or ""
})
