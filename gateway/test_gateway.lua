-- Run with: lua gateway/test_gateway.lua (from the repository root).
local token = string.rep("a", 64)
local secret = string.rep("b", 64)
local calls = 0
local output
local output_code

package.preload["nixio.fs"] = function()
    return { readfile = function(path)
        if path == "/etc/ilink/device_token" then return token .. "\n" end
        if path == "/etc/ilink/rpcd_password" then return secret .. "\n" end
    end }
end
package.preload["luci.sys"] = function()
    return { call = function(_) end }
end
package.preload["ubus"] = function()
    return { connect = function()
        calls = calls + 1
        return {
            call = function(_, object, method, arguments)
                if object == "session" then
                    assert(arguments.username == "ilink")
                    assert(arguments.password == secret)
                    return { ubus_rpc_session = "test-session" }
                end
                assert(arguments.ubus_rpc_session == "test-session")
                if object == "system" and method == "board" then
                    return { hostname = "test-router", model = "test-model", kernel = "test" }
                end
                if object == "system" and method == "info" then
                    return { uptime = 42, load = { 0.1 }, memory = { total = 100, available = 50 } }
                end
                if object == "luci-rpc" and method == "getHostHints" then
                    return { ["00:11:22:33:44:55"] = { ipaddrs = { "192.0.2.2" }, name = "phone" } }
                end
                if object == "luci-rpc" and method == "getWirelessDevices" then
                    return { radio0 = { interfaces = { { config = { ssid = "test-wifi" }, iwinfo = {} } } } }
                end
                if object == "luci" and method == "getMountPoints" then
                    return { { mount = "/mnt/data_sdb1", available = 1000, size = 2000 } }
                end
                if object:match("^network%.interface%.") then
                    return { interface = object:gsub("network%.interface%.", ""), up = true }
                end
                error("unexpected RPC: " .. object .. "." .. method)
            end,
            close = function(_) end
        }
    end }
end
package.preload["openclash"] = function()
    return { status = function() return { running = true } end }
end
package.preload["files"] = function()
    return { list = function(body)
        assert(body.path == "docs")
        return { entries = {} }
    end }
end
_G.uhttpd = { send = function(value)
    output = (output or "") .. value
    output_code = tonumber(output:match("^Status: (%d+)"))
end }

assert(loadfile("gateway/gateway.lua"))()

local function request(path, authorization, method, request_body)
    output, output_code = nil, nil
    handle_request({
        PATH_INFO = path,
        REQUEST_METHOD = method or "GET",
        HTTP_AUTHORIZATION = authorization,
        REQUEST_BODY = request_body or "{}"
    })
    assert(output, "missing response")
    return output_code, output
end

local code, body = request("/v1/status", "Bearer " .. token)
assert(code == 200 and body:find('"hostname":"test%-router"'))
code = request("/v1/status")
assert(code == 401, "missing token must be rejected")
code = request("/v1/status", "Bearer " .. string.rep("c", 64))
assert(code == 401, "wrong token must be rejected")
for _ = 1, 100 do code = request("/v1/status") end
assert(code == 429, "invalid authentication must also be rate limited")
os.execute("sleep 1")
code = request("/v1/status", "Bearer " .. token, "POST")
assert(code == 405, "write methods must be rejected")
local before = calls
code = request("/ubus", "Bearer " .. token)
assert(code == 404 and calls == before, "generic ubus must not be routed")
code = request("/cgi-bin/luci", "Bearer " .. token)
assert(code == 404 and calls == before, "LuCI must not be routed")
code = request("/v1/openclash/status", "Bearer " .. token)
assert(code == 200, "fixed OpenClash route must work")
code = request("/v1/files/list", "Bearer " .. token, "POST", '{"path":"docs"}')
assert(code == 200, "fixed file route must work")
code = request("/v1/files/list", "Bearer " .. token)
assert(code == 405, "file mutations must not be accepted over GET")
code = request("/v1/openclash/unknown", "Bearer " .. token)
assert(code == 404, "unknown controller routes must not be proxied")
code, body = request("/clients", "Bearer " .. token)
assert(code == 200 and body:find("192%.0%.2%.2"))
code, body = request("/network", "Bearer " .. token)
assert(code == 200 and body:find("test%-wifi"))
assert(not body:find(secret, 1, true), "internal password must never be returned")
for _ = 1, 100 do code = request("/v1/status", "Bearer " .. token) end
assert(code == 429, "rate limit must apply")
print("Gateway auth, route, read-only RPC and rate-limit tests: OK")
