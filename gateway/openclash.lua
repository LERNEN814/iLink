-- Fixed Mihomo endpoints. The controller secret never leaves the router.
local json = require "luci.jsonc"
local nixio = require "nixio"
local fs = require "nixio.fs"
local urlcode = require "urlcode"
local M = {}

local function valid_name(value)
    return type(value) == "string" and #value > 0 and #value <= 512 and
        not value:find("%z") and not value:find("[\r\n]") and
        not value:find("[/\\]") and not value:find("%.%.")
end

local function valid_connection(value)
    return type(value) == "string" and value:match("^[%x%-]+$") and #value <= 64
end

local function connection()
    local socket = nixio.connect("127.0.0.1", 9090)
    if not socket then error("OpenClash is not reachable") end
    socket:setopt("socket", "rcvtimeo", 15)
    socket:setopt("socket", "sndtimeo", 10)
    return socket
end

local function request(method, path, body)
    local secret = io.open("/etc/ilink/clash_secret"):read("*l")
    local payload = body and json.stringify(body) or ""
    local socket = connection()
    local head = table.concat({
        method .. " " .. path .. " HTTP/1.1\r\n",
        "Host: 127.0.0.1\r\n",
        "Authorization: Bearer " .. secret .. "\r\n",
        "Connection: close\r\n",
        "Content-Type: application/json\r\n",
        "Content-Length: " .. #payload .. "\r\n\r\n",
        payload
    })
    if not socket:send(head) then socket:close(); error("controller write failed") end
    local chunks = {}
    repeat
        local chunk = socket:recv(16384)
        if chunk and #chunk > 0 then chunks[#chunks + 1] = chunk end
    until not chunk or #chunk == 0
    socket:close()
    local raw = table.concat(chunks)
    local header, response_body = raw:match("^(.-)\r\n\r\n(.*)$")
    if not header then error("invalid controller response") end
    local code = tonumber(header:match("^HTTP/%d%.%d%s+(%d+)"))
    if not code or code < 200 or code >= 300 then error("controller request failed") end
    if header:lower():find("transfer%-encoding:%s*chunked") then
        local decoded, position = {}, 1
        while true do
            local line_start, line_end, size_text = response_body:find("^(%x+)[^\r\n]*\r\n", position)
            if not line_start then error("invalid chunked response") end
            local size = tonumber(size_text, 16)
            position = line_end + 1
            if size == 0 then break end
            decoded[#decoded + 1] = response_body:sub(position, position + size - 1)
            position = position + size
            if response_body:sub(position, position + 1) ~= "\r\n" then
                error("invalid chunk terminator")
            end
            position = position + 2
        end
        response_body = table.concat(decoded)
    end
    if #response_body == 0 then return {} end
    return json.parse(response_body) or error("invalid controller JSON")
end

local function clean_node(node)
    local history = node.history or {}
    local last = history[#history] or {}
    return {
        name = node.name,
        type = node.type,
        alive = node.alive == true,
        delay = tonumber(last.delay) or 0,
        now = node.now,
        all = type(node.all) == "table" and node.all or nil,
        history = type(history) == "table" and history or nil
    }
end

function M.status()
    local version = request("GET", "/version")
    local config = request("GET", "/configs")
    local connections = request("GET", "/connections")
    local upload, download = 0, 0
    for _, item in pairs(connections.connections or {}) do
        upload = upload + (tonumber(item.upload) or 0)
        download = download + (tonumber(item.download) or 0)
    end
    return {
        running = true,
        version = version.version,
        mode = config.mode,
        mixedPort = config["mixed-port"],
        config = (fs.readfile("/etc/ilink/clash_config") or ""):gsub("%s+", ""),
        connections = #(connections.connections or {}),
        upload = upload,
        download = download,
        uploadTotal = connections.uploadTotal or 0,
        downloadTotal = connections.downloadTotal or 0
    }
end

function M.connections()
    return { connectionList = request("GET", "/connections").connections or {} }
end

function M.groups()
    local proxies = request("GET", "/proxies").proxies or {}
    local result = {}
    for _, proxy in pairs(proxies) do
        if proxy.type == "Selector" or proxy.type == "URLTest" or proxy.type == "Fallback" then
            local group = clean_node(proxy)
            local nodes = {}
            for _, name in ipairs(group.all or {}) do
                if proxies[name] then nodes[#nodes + 1] = clean_node(proxies[name]) end
            end
            group.nodes = nodes
            result[#result + 1] = group
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return { groups = result }
end

function M.configs()
    local names = {}
    for name in fs.dir("/etc/openclash/config") do
        if name:match("%.ya?ml$") and #name <= 128 and not name:find("%.%.") then
            local stat = fs.stat("/etc/openclash/config/" .. name)
            if stat and stat.type == "reg" then names[#names + 1] = name end
        end
    end
    table.sort(names)
    local current = (fs.readfile("/etc/ilink/clash_config") or ""):gsub("%s+", "")
    return { configs = names, current = fs.basename(current) }
end

function M.mode(body)
    local mode = body.mode
    if mode ~= "rule" and mode ~= "global" and mode ~= "direct" then
        error("invalid mode")
    end
    request("PATCH", "/configs", { mode = mode })
    return { mode = mode }
end

-- Privileged actions run through the ACL-gated rpcd helper, never as a shell.
local function action(name, arguments)
    local connection = require("ubus").connect()
    if not connection then error("ubus unavailable") end
    local result, code = connection:call("ilink-action", name, arguments or {})
    connection:close()
    if not result or (code and code ~= 0) then error("action failed") end
    return result
end

function M.service(body)
    local op = body.op
    if op ~= "start" and op ~= "stop" and op ~= "restart" then
        error("invalid service operation")
    end
    return action("openclash", { op = op })
end

function M.switch_config(body)
    local name = body.name
    if type(name) ~= "string" or not name:match("^[%w_%-%.]+%.ya?ml$") or name:find("%.%.") then
        error("invalid config name")
    end
    return action("switch-config", { name = name })
end

function M.select(body)
    if not valid_name(body.group) or not valid_name(body.proxy) then
        error("invalid group or proxy")
    end
    request("PUT", "/proxies/" .. urlcode.escape(body.group), { name = body.proxy })
    return { changed = true }
end

function M.test_delay(body)
    if not valid_name(body.proxy) then error("invalid proxy") end
    local result = request("GET", "/proxies/" .. urlcode.escape(body.proxy) ..
        "/delay?timeout=5000&url=" .. urlcode.escape("https://www.gstatic.com/generate_204"))
    return { proxy = body.proxy, delay = tonumber(result.delay) or 0 }
end

function M.close(body)
    if not valid_connection(body.id) then error("invalid connection id") end
    request("DELETE", "/connections/" .. body.id)
    return { closed = true }
end

return M
