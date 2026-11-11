-- iLink v0.2: fixed, read-only API. No caller-supplied RPC names or commands.
local json = require "luci.jsonc"
local ubus = require "ubus"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local urlcode = require "urlcode"

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

local function ip_to_int(value)
    local a, b, c, d = tostring(value):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    return tonumber(a) * 16777216 + tonumber(b) * 65536 + tonumber(c) * 256 + tonumber(d)
end

local function in_subnet(ip, network, mask)
    local address, base, bits = ip_to_int(ip), ip_to_int(network), ip_to_int(mask)
    if not address or not base or not bits then return false end
    local shift = 32
    local size = 0
    while size < 32 and bits % 2 == 0 do
        bits = math.floor(bits / 2)
        size = size + 1
    end
    if size == 0 then return true end
    local divisor = 2 ^ size
    return math.floor(address / divisor) == math.floor(base / divisor)
end

local function lease_hostnames()
    local names = {}
    local handle = io.open("/tmp/dhcp.leases", "r")
    if not handle then return names end
    for line in handle:lines() do
        local mac, host = line:match("^%S+%s+(%S+)%s+%S+%s+(%S+)")
        if mac then names[mac:upper()] = host ~= "*" and host or nil end
    end
    handle:close()
    return names
end

local function dotted_mask(mask)
    -- ubus reports the prefix length (24), not a dotted mask.
    local bits
    if type(mask) == "number" and mask <= 32 then
        bits = mask == 0 and 0 or (4294967295 - (2 ^ (32 - mask) - 1))
    elseif type(mask) == "string" then
        bits = ip_to_int(mask)
    end
    if not bits then bits = 4294967295 - 255 end
    return string.format("%d.%d.%d.%d",
        math.floor(bits / 16777216) % 256,
        math.floor(bits / 65536) % 256,
        math.floor(bits / 256) % 256,
        bits % 256)
end

local function lan_subnet()
    local connection = connect()
    local lan = connection:call("network.interface.lan", "status", {
        ubus_rpc_session = rpc_session
    })
    connection:close()
    local address = lan and lan["ipv4-address"] and lan["ipv4-address"][1]
    if not address then return nil end
    return {
        address = address.address,
        mask = dotted_mask(address.mask)
    }
end

local function clients()
    local subnet = lan_subnet()
    local leases = lease_hostnames()
    local connection = connect()
    local hints = call(connection, "luci-rpc", "getHostHints")
    connection:close()
    local result, seen = {}, {}
    for mac, hint in pairs(hints) do
        local key = type(mac) == "string" and mac:upper() or nil
        -- Only LAN neighbours belong in the device list: the ARP/neighbour
        -- table also carries docker bridges, tunnel peers and stale entries.
        if key and key:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") and
            not key:match("^02:42:") then
            local addresses = type(hint.ipaddrs) == "table" and hint.ipaddrs or {}
            local ip = addresses[1]
            local allowed = subnet and ip and in_subnet(ip, subnet.address, subnet.mask)
            if allowed and not seen[key] and ip ~= subnet.address then
                seen[key] = true
                result[#result + 1] = {
                    macaddr = key,
                    ipaddr = ip,
                    hostname = hint.name or leases[key],
                    ipv6addrs = hint.ip6addrs,
                    vendor = hint.vendor
                }
            end
        end
    end
    table.sort(result, function(a, b)
        return (ip_to_int(a.ipaddr) or 0) < (ip_to_int(b.ipaddr) or 0)
    end)
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
    ["openclash/subscription"] = { module = "openclash", action = "subscription", method = "POST" },
    ["openclash/configs"] = { module = "openclash", action = "configs", method = "GET" },
    ["openclash/mode"] = { module = "openclash", action = "mode", method = "POST" },
    ["openclash/service"] = { module = "openclash", action = "service", method = "POST" },
    ["openclash/switch-config"] = { module = "openclash", action = "switch_config", method = "POST" },
    ["files/list"] = { module = "files", action = "list", method = "POST" },
    ["files/mkdir"] = { module = "files", action = "mkdir", method = "POST" },
    ["files/rename"] = { module = "files", action = "rename", method = "POST" },
    ["files/remove"] = { module = "files", action = "remove", method = "POST" },
    ["files/download"] = { module = "files", action = "download", method = "POST" },
    ["files/stream-ticket"] = { module = "files", action = "stream_ticket", method = "POST" },
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
    ["alist/download"] = { module = "alist", action = "download", method = "POST" },
    ["downloader/submit"] = { module = "downloader", action = "submit", method = "POST" },
    ["downloader/jobs"] = { module = "downloader", action = "jobs", method = "GET" },
    ["downloader/remove"] = { module = "downloader", action = "remove", method = "POST" },
    ["system/services"] = { module = "systeminfo", action = "services", method = "GET" },
    ["system/updates"] = { module = "systeminfo", action = "updates", method = "GET" },
    ["openclash/group-delay"] = { module = "openclash", action = "group_delay", method = "POST" },
    ["openclash/ipcheck"] = { module = "openclash", action = "ipcheck", method = "GET" },
    ["system/traffic"] = { module = "systeminfo", action = "traffic", method = "GET" },
    ["system/exec"] = { module = "systeminfo", action = "exec", method = "POST" },
    ["system/network-snapshot"] = { module = "systeminfo", action = "network_snapshot", method = "POST" },
    ["system/network-backups"] = { module = "systeminfo", action = "network_backups", method = "GET" },
    ["system/network-restore"] = { module = "systeminfo", action = "network_restore", method = "POST" },
    ["system/network-confirm"] = { module = "systeminfo", action = "network_confirm", method = "POST" },
    ["system/firmware"] = { module = "systeminfo", action = "firmware", method = "GET" },
    ["system/upgrade"] = { module = "systeminfo", action = "upgrade", method = "POST" },
    ["system/upgrade-status"] = { module = "systeminfo", action = "upgrade_status", method = "GET" }
}

-- Query lookup for the media stream route.
local query_value = urlcode.query_value

function handle_request(env)
    local path = env.PATH_INFO or ""
    -- Media streaming answers by stream ticket or device token and speaks raw
    -- bytes, so it bypasses the JSON envelope and the JSON rate limiter.
    if path == "/v1/files/stream" then
        local query = env.QUERY_STRING or ""
        if query_value(query, "ticket") ~= "" then
            local ok, resolved = pcall(
                require("files").stream_path,
                query_value(query, "ticket"),
                query_value(query, "path")
            )
            if not ok then
                audit("stream ticket rejected: " .. tostring(resolved))
                return respond(401, { error = "unauthorized" })
            end
            env.STREAM_PATH = resolved
        elseif not authenticated(env) then
            audit("authentication failed")
            return respond(401, { error = "unauthorized" })
        else
            -- Downloads authenticate with the device token, not a ticket.
            local requested = query_value(query, "path")
            if requested == "" then
                return respond(400, { error = "missing_path" })
            end
            env.STREAM_PATH = requested
        end
        local ok, err = pcall(require("files").stream_raw, env)
        if not ok then
            audit("stream failed: " .. tostring(err))
            return respond(503, { error = "unavailable" })
        end
        return
    end
    if path == "/v1/files/upload-raw" then
        if env.REQUEST_METHOD ~= "POST" then
            return respond(405, { error = "method_not_allowed" })
        end
        if not authenticated(env) then
            audit("authentication failed")
            return respond(401, { error = "unauthorized" })
        end
        local ok, data = pcall(require("files").upload_raw, env)
        if not ok then
            audit("upload failed: " .. tostring(data))
            return respond(503, { error = "unavailable" })
        end
        return respond(200, { apiVersion = 1, data = data })
    end

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
