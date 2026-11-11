#!/usr/bin/lua
package.path = "/usr/lib/ilink/?.lua;" .. package.path
dofile("/usr/lib/ilink/gateway.lua")
local length = tonumber(os.getenv("CONTENT_LENGTH")) or 0
if length > 16384 then os.exit(0) end
handle_request({
    PATH_INFO = os.getenv("SCRIPT_NAME"),
    REQUEST_METHOD = os.getenv("REQUEST_METHOD"),
    HTTP_AUTHORIZATION = os.getenv("HTTP_AUTHORIZATION"),
    QUERY_STRING = os.getenv("QUERY_STRING") or "",
    HTTP_RANGE = os.getenv("HTTP_RANGE") or "",
    REQUEST_BODY = length > 0 and io.read(length) or "{}"
})
