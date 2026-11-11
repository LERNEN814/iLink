#!/usr/bin/lua
-- Raw-body upload entry. module.cgi caps bodies at 16 KB because they are
-- parsed as JSON; uploads stream straight to a staging file instead, so the
-- only limit is free space on the target filesystem.
package.path = "/usr/lib/ilink/?.lua;" .. package.path
dofile("/usr/lib/ilink/gateway.lua")
handle_request({
    PATH_INFO = "/v1/files/upload-raw",
    REQUEST_METHOD = os.getenv("REQUEST_METHOD"),
    HTTP_AUTHORIZATION = os.getenv("HTTP_AUTHORIZATION"),
    QUERY_STRING = os.getenv("QUERY_STRING") or "",
})
