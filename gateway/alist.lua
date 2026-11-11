-- AList bridge: fixed endpoints, credentials live only on the router.
local json = require "luci.jsonc"
local nixio = require "nixio"
local fs = require "nixio.fs"
local urlcode = require "urlcode"
local util = require "ilink_util"
local M = {}

local HOST, PORT = "127.0.0.1", 5244
local CREDENTIALS = "/etc/ilink/alist_credentials"
local MAX_BODY = 40 * 1024 * 1024
local MAX_UPLOAD = 32 * 1024 * 1024
local token, token_at

local function read_credentials()
    local raw = fs.readfile(CREDENTIALS)
    if not raw then error("AList credentials are not configured") end
    local user, password = raw:match("^([^\r\n]+)[\r\n]+([^\r\n]+)")
    if not user or not password or password == "" then
        error("AList credentials are incomplete")
    end
    return user, password
end

local temp_path = function(suffix) return util.temp_path("alist", suffix) end
local shell_quote = util.shell_quote

local function http(method, path, headers, body, timeout)
    local socket = nixio.connect(HOST, PORT)
    if not socket then error("AList is not reachable") end
    socket:setopt("socket", "rcvtimeo", timeout or 20)
    socket:setopt("socket", "sndtimeo", 15)
    local head = { method .. " " .. path .. " HTTP/1.1\r\n", "Host: 127.0.0.1\r\n" }
    for name, value in pairs(headers or {}) do
        head[#head + 1] = name .. ": " .. value .. "\r\n"
    end
    head[#head + 1] = "Content-Length: " .. #(body or "") .. "\r\n"
    head[#head + 1] = "Connection: close\r\n\r\n"
    if not socket:send(table.concat(head) .. (body or "")) then
        socket:close()
        error("AList write failed")
    end
    local chunks, total = {}, 0
    while true do
        local chunk = socket:recv(16384)
        if not chunk or #chunk == 0 then break end
        total = total + #chunk
        if total > MAX_BODY then socket:close(); error("AList response too large") end
        chunks[#chunks + 1] = chunk
    end
    socket:close()
    local raw = table.concat(chunks)
    local header, payload = raw:match("^(.-)\r\n\r\n(.*)$")
    if not header then error("invalid AList response") end
    local code = tonumber(header:match("^HTTP/%d%.%d%s+(%d+)")) or 0
    if header:lower():find("transfer%-encoding:%s*chunked") then
        local decoded, position = {}, 1
        while true do
            local _, stop, size_text = payload:find("^(%x+)[^\r\n]*\r\n", position)
            if not stop then break end
            local size = tonumber(size_text, 16)
            position = stop + 1
            if size == 0 then break end
            decoded[#decoded + 1] = payload:sub(position, position + size - 1)
            position = position + size + 2
        end
        payload = table.concat(decoded)
    end
    return code, payload
end

local function login()
    if token and os.time() - token_at < 3600 then return token end
    local user, password = read_credentials()
    local code, body = http("POST", "/api/auth/login",
        { ["Content-Type"] = "application/json" },
        json.stringify({ username = user, password = password }))
    if code ~= 200 then error("AList login rejected") end
    local parsed = json.parse(body)
    local value = parsed and parsed.data and parsed.data.token
    if not value then error("AList login failed") end
    token, token_at = value, os.time()
    return token
end

local function api(path, payload)
    local code, body = http("POST", path, {
        ["Authorization"] = login(),
        ["Content-Type"] = "application/json"
    }, json.stringify(payload or {}))
    if code ~= 200 then error("AList request failed") end
    local parsed = json.parse(body)
    if not parsed then error("invalid AList response") end
    if parsed.code ~= 200 then
        error("AList: " .. tostring(parsed.message or parsed.code))
    end
    return parsed.data or {}
end

local function clean_path(value, allow_root)
    if type(value) ~= "string" or #value > 1024 then error("invalid path") end
    if value:find("%.%.") or value:find("[\\%z\r\n]") then error("invalid path") end
    if not value:match("^/") then value = "/" .. value end
    if #value > 1 and value:match("/$") then value = value:sub(1, -2) end
    if value == "/" and not allow_root then error("invalid path") end
    return value
end

local valid_name = util.valid_name
local encode_file = util.encode_file
local decode_to = util.decode_to

local function http(method, path, headers, body, timeout)
    local socket = nixio.connect(HOST, PORT)
    if not socket then error("AList is not reachable") end
    socket:setopt("socket", "rcvtimeo", timeout or 20)
    socket:setopt("socket", "sndtimeo", 15)
    local head = { method .. " " .. path .. " HTTP/1.1\r\n", "Host: 127.0.0.1\r\n" }
    for name, value in pairs(headers or {}) do
        head[#head + 1] = name .. ": " .. value .. "\r\n"
    end
    head[#head + 1] = "Content-Length: " .. #(body or "") .. "\r\n"
    head[#head + 1] = "Connection: close\r\n\r\n"
    if not socket:send(table.concat(head) .. (body or "")) then
        socket:close()
        error("AList write failed")
    end
    local chunks, total = {}, 0
    while true do
        local chunk = socket:recv(16384)
        if not chunk or #chunk == 0 then break end
        total = total + #chunk
        if total > MAX_BODY then socket:close(); error("AList response too large") end
        chunks[#chunks + 1] = chunk
    end
    socket:close()
    local raw = table.concat(chunks)
    local header, payload = raw:match("^(.-)\r\n\r\n(.*)$")
    if not header then error("invalid AList response") end
    local code = tonumber(header:match("^HTTP/%d%.%d%s+(%d+)")) or 0
    if header:lower():find("transfer%-encoding:%s*chunked") then
        local decoded, position = {}, 1
        while true do
            local _, stop, size_text = payload:find("^(%x+)[^\r\n]*\r\n", position)
            if not stop then break end
            local size = tonumber(size_text, 16)
            position = stop + 1
            if size == 0 then break end
            decoded[#decoded + 1] = payload:sub(position, position + size - 1)
            position = position + size + 2
        end
        payload = table.concat(decoded)
    end
    return code, payload
end

local function login()
    if token and os.time() - token_at < 3600 then return token end
    local user, password = read_credentials()
    local code, body = http("POST", "/api/auth/login",
        { ["Content-Type"] = "application/json" },
        json.stringify({ username = user, password = password }))
    if code ~= 200 then error("AList login rejected") end
    local parsed = json.parse(body)
    local value = parsed and parsed.data and parsed.data.token
    if not value then error("AList login failed") end
    token, token_at = value, os.time()
    return token
end

local function api(path, payload)
    local code, body = http("POST", path, {
        ["Authorization"] = login(),
        ["Content-Type"] = "application/json"
    }, json.stringify(payload or {}))
    if code ~= 200 then error("AList request failed") end
    local parsed = json.parse(body)
    if not parsed then error("invalid AList response") end
    if parsed.code ~= 200 then
        error("AList: " .. tostring(parsed.message or parsed.code))
    end
    return parsed.data or {}
end

local function clean_path(value, allow_root)
    if type(value) ~= "string" or #value > 1024 then error("invalid path") end
    if value:find("%.%.") or value:find("[\\%z\r\n]") then error("invalid path") end
    if not value:match("^/") then value = "/" .. value end
    if #value > 1 and value:match("/$") then value = value:sub(1, -2) end
    if value == "/" and not allow_root then error("invalid path") end
    return value
end

local function join(dir, name)
    return (dir == "/" and "/" or dir .. "/") .. name
end

function M.list(body)
    local path = clean_path(body.path or "/", true)
    local data = api("/api/fs/list", {
        path = path, page = 1, per_page = 500, refresh = body.refresh == true
    })
    local entries = {}
    for _, item in ipairs(data.content or {}) do
        if item.name ~= "." and item.name ~= ".." then
            entries[#entries + 1] = {
                name = item.name,
                path = join(path, item.name),
                directory = item.is_dir == true,
                size = tonumber(item.size) or 0,
                modified = 0
            }
        end
    end
    return { path = path, entries = entries, write = data.write == true }
end

function M.mkdir(body)
    local dir = clean_path(body.dir or "/", true)
    if not valid_name(body.name) then error("invalid name") end
    api("/api/fs/mkdir", { path = join(dir, body.name) })
    return { created = true }
end

function M.rename(body)
    local path = clean_path(body.path)
    if not valid_name(body.name) then error("invalid name") end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == "" then parent = "/" end
    api("/api/fs/rename", { path = path, name = body.name })
    return { renamed = true }
end

function M.remove(body)
    local dir = clean_path(body.dir or "/", true)
    local names = body.names
    if type(names) ~= "table" or #names == 0 then error("invalid names") end
    if #names > 200 then error("too many names") end
    for _, name in ipairs(names) do
        if not valid_name(name) then error("invalid name") end
    end
    api("/api/fs/remove", { dir = dir, names = names })
    return { deleted = true }
end

function M.upload(body)
    local dir = clean_path(body.dir or "/", true)
    if not valid_name(body.name) then error("invalid name") end
    if type(body.base64) ~= "string" or #body.base64 == 0 then error("empty upload") end
    if #body.base64 > MAX_UPLOAD * 2 then error("file too large") end
    local target = join(dir, body.name)
    local staged = temp_path(".bin")
    decode_to(body.base64, staged)
    local stat = fs.stat(staged)
    if not stat or stat.size == 0 then fs.unlink(staged); error("upload failed") end
    local handle = io.open(staged, "rb")
    local payload = handle and handle:read("*a") or ""
    if handle then handle:close() end
    fs.unlink(staged)
    local code = http("PUT", "/api/fs/put", {
        ["Authorization"] = login(),
        ["File-Path"] = urlcode.escape_path(target),
        ["Content-Type"] = "application/octet-stream",
        ["Content-Length"] = tostring(#payload)
    }, payload, 120)
    if code ~= 200 then error("AList upload failed") end
    return { uploaded = true, size = #payload }
end

function M.download(body)
    local path = clean_path(body.path)
    local data = api("/api/fs/get", { path = path })
    local raw = data.raw_url
    if type(raw) ~= "string" or not raw:match("^https?://") then
        error("AList did not return a download url")
    end
    local target = raw:match("^https?://[^/]+(/.*)$")
    if not target then error("invalid download url") end
    local code, payload = http("GET", target, {
        ["Authorization"] = login()
    }, nil, 120)
    if code ~= 200 then error("AList download failed") end
    if #payload > MAX_BODY then error("file too large") end
    local staged = temp_path(".bin")
    if not fs.writefile(staged, payload) then error("cannot stage download") end
    local encoded = encode_file(staged)
    fs.unlink(staged)
    return { name = data.name or "file", size = #payload, base64 = encoded }
end

return M
