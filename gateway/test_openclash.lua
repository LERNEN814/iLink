package.path = "gateway/?.lua;" .. package.path
local json = require "luci.jsonc"
local secret = "controller-test-secret"
local requests = {}
local next_raw

local function response(value)
    local body = json.stringify(value)
    local chunked = string.format("%X\r\n%s\r\n0\r\n\r\n", #body, body)
    return "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" .. chunked
end

package.preload["nixio"] = function()
    return { connect = function()
        local position = 1
        return {
            setopt = function() end,
            send = function(_, data)
                requests[#requests + 1] = data
                local path = data:match("^%u+%s+([^%s]+)")
                if path == "/version" then
                    next_raw = response({ version = "test-core" })
                elseif path == "/configs" then
                    next_raw = response({ mode = "rule", ["mixed-port"] = 7893 })
                elseif path == "/connections" then
                    next_raw = response({ connections = { { id = "abc-123", upload = 2, download = 3 } } })
                elseif path == "/proxies" then
                    next_raw = response({ proxies = {
                        ["Proxy Select"] = { name = "Proxy Select", type = "Selector", now = "Node 1", all = { "Node 1" } },
                        ["Node 1"] = { name = "Node 1", type = "Shadowsocks", alive = true, history = { { delay = 123 } } }
                    } })
                elseif path:find("/delay", 1, true) then
                    next_raw = response({ delay = 88 })
                else
                    next_raw = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n"
                end
                return #data
            end,
            recv = function()
                if position > #next_raw then return nil end
                local part = next_raw:sub(position, position + 97)
                position = position + #part
                return part
            end,
            close = function() end
        }
    end }
end
package.preload["nixio.fs"] = function()
    return { readfile = function() return "/etc/openclash/config/test.yaml\n" end }
end
io.open = function(path)
    assert(path == "/etc/ilink/clash_secret")
    return { read = function() return secret .. "\n" end }
end

local clash = require "openclash"
local status = clash.status()
assert(status.running and status.version == "test-core")
assert(status.connections == 1 and status.download == 3)
assert(status.config == "/etc/openclash/config/test.yaml")
assert(not json.stringify(status):find(secret, 1, true))
local groups = clash.groups().groups
assert(#groups == 1 and groups[1].nodes[1].delay == 123)
assert(clash.select({ group = "Proxy Select", proxy = "Node 1" }).changed)
assert(requests[#requests]:find("PUT /proxies/Proxy%20Select", 1, true))
assert(clash.test_delay({ proxy = "Node 1" }).delay == 88)
assert(clash.close({ id = "abc-123" }).closed)
for _, body in ipairs({
    { group = "../configs", proxy = "Node 1" },
    { group = "Proxy Select", proxy = "Node 1\r\nX-Test: injected" },
    { group = "Proxy/Admin", proxy = "Node 1" }
}) do
    assert(not pcall(clash.select, body), "invalid proxy input must be rejected")
end
assert(not pcall(clash.close, { id = "../configs" }))
print("OpenClash chunked HTTP, filtering and fixed-route tests: OK")
