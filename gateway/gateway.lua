-- iLink v0.2: fixed, read-only API. No caller-supplied RPC names or commands.
local json = require "luci.jsonc"
local ubus = require "ubus"
local fs = require "nixio.fs"
local sys = require "luci.sys"

local TOKEN_FILE = "/etc/ilink/device_token"
local RPC_PASSWORD_FILE = "/etc/ilink/rpcd_password"
local rpc_session
local rpc_session_at = 0
local bucket_at = 0
local bucket_count = 0

local function read_secret(path)
    local value = fs.readfile(path)
    return value and value:gsub("%s+", "") or nil
end

local function token_matches(presented, expected)
    if type(presented) ~= "string" or not presented:match("^[0-9a-fA-F]+$") then
        return false
    end
    -- Fixed-work comparison; length is checked only after every byte is read.
    local difference = #presented ~= #expected and 1 or 0
    for index = 1, 64 do
        if presented:byte(index) ~= expected:byte(index) then
            difference = difference + 1
        end
    end
    return difference == 0
end

local function authenticated(env)
    local header = env.HTTP_AUTHORIZATION
    if type(header) ~= "string" or #header > 96 then return false end
    local presented = header:match("^Bearer ([0-9a-fA-F]+)$")
    local expected = read_secret(TOKEN_FILE)
    return expected and #expected == 64 and token_matches(presented, expected)
end

local function audit(message)
    sys.call("logger -t ilink-gateway '" .. message:gsub("[^%w%.:%-_ ]", "?") .. "'")
end

local function connect()
    local connection = ubus.connect()
    if not connection then error("ubus unavailable") end
    if not rpc_session or os.time() - rpc_session_at > 240 then
        local password = read_secret(RPC_PASSWORD_FILE)
        if not password then error("internal credential unavailable") end
        local login = connection:call("session", "login", {
            username = "ilink",
            password = password,
            timeout = 300
        })
        rpc_session = login and login.ubus_rpc_session or nil
        if not rpc_session then
            connection:close()
            error("internal login failed")
        end
        rpc_session_at = os.time()
    end
    return connection
end

local function call(connection, object, method, arguments)
    arguments = arguments or {}
    arguments.ubus_rpc_session = rpc_session
    local result = connection:call(object, method, arguments)
    if not result then error("internal RPC denied") end
    return result
end

local function status()
    local connection = connect()
    local board = call(connection, "system", "board")
    local info = call(connection, "system", "info")
    local mounts = call(connection, "luci", "getMountPoints")
    connection:close()
    return {
        hostname = board.hostname,
        model = board.model,
        kernel = board.kernel,
        release = board.release and board.release.description or nil,
        uptime = info.uptime,
        localtime = info.localtime,
        load = info.load,
        memory = info.memory,
        mounts = mounts
    }
end

local function clients()
    local connection = connect()
    local hints = call(connection, "luci-rpc", "getHostHints")
    connection:close()
    local result = {}
    for mac, hint in pairs(hints) do
        if type(mac) == "string" and mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
            local addresses = type(hint.ipaddrs) == "table" and hint.ipaddrs or {}
            result[#result + 1] = {
                macaddr = mac,
                ipaddr = addresses[1],
                hostname = hint.name,
                ipv6addrs = hint.ip6addrs,
                vendor = hint.vendor
            }
        end
    end
    table.sort(result, function(a, b) return (a.ipaddr or "") < (b.ipaddr or "") end)
    return { clients = result }
end

local function network()
    local connection = connect()
    local radios = call(connection, "luci-rpc", "getWirelessDevices")
    local interfaces = {}
    for _, name in ipairs({ "lan", "wan", "wan6" }) do
        local value = connection:call("network.interface." .. name, "status", {
            ubus_rpc_session = rpc_session
        })
        if value then interfaces[#interfaces + 1] = value end
    end
    connection:close()

    local wireless = {}
    for radio, value in pairs(radios) do
        for _, item in ipairs(value.interfaces or {}) do
            local config = item.config or {}
            local iwinfo = item.iwinfo or {}
            local encryption = iwinfo.encryption or {}
            wireless[#wireless + 1] = {
                radio = radio,
                ssid = config.ssid or iwinfo.ssid,
                mode = config.mode or iwinfo.mode,
                channel = iwinfo.channel or value.channel,
                band = iwinfo.band or value.band,
                up = not config.disabled or config.disabled == "0",
                encryption = table.concat(encryption.authentication or {}, "+")
            }
        end
    end
    return { interfaces = interfaces, wireless = wireless }
end

local routes = {
    ["/status"] = status,
    ["/v1/status"] = status,
    ["/clients"] = clients,
    ["/v1/clients"] = clients,
    ["/network"] = network,
    ["/v1/network"] = network
}

local status_text = {
    [200] = "OK", [400] = "Bad Request", [401] = "Unauthorized", [404] = "Not Found",
    [405] = "Method Not Allowed", [429] = "Too Many Requests",
    [503] = "Service Unavailable"
}

local function respond(code, value)
    local body = json.stringify(value)
    local send = type(uhttpd) == "table" and uhttpd.send or io.write
    send("Status: " .. code .. " " .. status_text[code] .. "\r\n")
    send("Content-Type: application/json; charset=utf-8\r\n")
    send("Cache-Control: no-store\r\n")
    send("X-Content-Type-Options: nosniff\r\n")
    send("Content-Length: " .. #body .. "\r\n\r\n")
    send(body)
end

local module_routes = {
    ["openclash/status"] = { module = "openclash", action = "status", method = "GET" },
    ["openclash/groups"] = { module = "openclash", action = "groups", method = "GET" },
    ["openclash/connections"] = { module = "openclash", action = "connections", method = "GET" },
    ["openclash/select"] = { module = "openclash", action = "select", method = "POST" },
    ["openclash/test-delay"] = { module = "openclash", action = "test_delay", method = "POST" },
    ["openclash/close"] = { module = "openclash", action = "close", method = "POST" },
    ["openclash/overview"] = { module = "openclash", action = "overview", method = "GET" },
    ["openclash/configs"] = { module = "openclash", action = "configs", method = "GET" },
    ["openclash/mode"] = { module = "openclash", action = "mode", method = "POST" },
    ["openclash/service"] = { module = "openclash", action = "service", method = "POST" },
    ["openclash/switch-config"] = { module = "openclash", action = "switch_config", method = "POST" },
    ["files/list"] = { module = "files", action = "list", method = "POST" },
    ["files/mkdir"] = { module = "files", action = "mkdir", method = "POST" },
    ["files/rename"] = { module = "files", action = "rename", method = "POST" },
    ["files/remove"] = { module = "files", action = "remove", method = "POST" },
    ["files/download"] = { module = "files", action = "download", method = "POST" },
    ["files/upload"] = { module = "files", action = "upload", method = "POST" },
    ["files/copy"] = { module = "files", action = "copy", method = "POST" },
    ["files/move"] = { module = "files", action = "move", method = "POST" },
    ["files/preview"] = { module = "files", action = "preview", method = "POST" },
    ["fastnet/quick"] = { module = "fastnet", action = "quick", method = "GET" },
    ["fastnet/nat"] = { module = "fastnet", action = "nat", method = "GET" },
    ["fastnet/ipv6"] = { module = "fastnet", action = "ipv6", method = "GET" },
    ["alist/list"] = { module = "alist", action = "list", method = "POST" },
    ["alist/mkdir"] = { module = "alist", action = "mkdir", method = "POST" },
    ["alist/rename"] = { module = "alist", action = "rename", method = "POST" },
    ["alist/remove"] = { module = "alist", action = "remove", method = "POST" },
    ["alist/upload"] = { module = "alist", action = "upload", method = "POST" },
    ["alist/download"] = { module = "alist", action = "download", method = "POST" }
}

function handle_request(env)
    local path = env.PATH_INFO or ""
    local handler = routes[path]
    local body = {}
    local module = module_routes[path:match("^/v1/(.+)$") or ""]
    if not handler and module then
        handler = function()
            return require(module.module)[module.action](body)
        end
    end
    if not handler then return respond(404, { error = "not_found" }) end
    if module and env.REQUEST_METHOD ~= module.method then
        return respond(405, { error = "method_not_allowed" })
    end
    if not module and env.REQUEST_METHOD ~= "GET" then
        return respond(405, { error = "method_not_allowed" })
    end
    if module and module.method == "POST" then
        local ok, decoded = pcall(json.parse, env.REQUEST_BODY or "{}")
        if not ok or type(decoded) ~= "table" then
            return respond(400, { error = "invalid_json" })
        end
        body = decoded
    end
    local now = os.time()
    if now ~= bucket_at then bucket_at, bucket_count = now, 0 end
    bucket_count = bucket_count + 1
    if bucket_count > 90 then return respond(429, { error = "rate_limited" }) end
    if not authenticated(env) then
        audit("authentication failed")
        return respond(401, { error = "unauthorized" })
    end

    local ok, data = pcall(handler)
    if not ok then
        -- Diagnostics go to the system log, never to the caller.
        audit("failed " .. path .. ": " .. tostring(data))
        return respond(503, { error = "unavailable" })
    end
    return respond(200, { apiVersion = 1, data = data })
end
