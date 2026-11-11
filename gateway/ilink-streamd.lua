#!/usr/bin/lua
-- Dedicated media streamer with HTTP Range support.
--
-- uhttpd's CGI environment drops the Range header (its env table is baked in
-- at compile time), so seeking was impossible through the gateway. This
-- process speaks HTTP itself and only listens on loopback; a second uhttpd
-- instance terminates TLS and forwards raw connections to it.
--
-- Access is gated by single-use tickets in /tmp/ilink-stream-tickets that the
-- gateway issues for one specific file, so the player never holds the device
-- token and a leaked URL is worth one file for fifteen minutes.
local nixio = require "nixio"
local fs = require "nixio.fs"

local PORT = tonumber(arg[1]) or 8092
local BIND_ADDR = arg[2] or "127.0.0.1"
local TICKET_DIR = "/tmp/ilink-stream-tickets"
local TICKET_TTL = 900
local CHUNK = 65536

local MIME = {
    mp4 = "video/mp4", mkv = "video/x-matroska", avi = "video/x-msvideo",
    mov = "video/quicktime", webm = "video/webm", flv = "video/x-flv",
    ts = "video/mp2t", ["m3u8"] = "application/vnd.apple.mpegurl",
    mp3 = "audio/mpeg", flac = "audio/flac", aac = "audio/aac",
    m4a = "audio/mp4", wav = "audio/x-wav", opus = "audio/opus",
    ogg = "audio/ogg", oga = "audio/ogg"
}

local function mime_of(path)
    local extension = path:match("%.([%w]+)$")
    return extension and MIME[extension:lower()] or "application/octet-stream"
end

-- Percent-decoding for the query string; the ticket is hex so only the path
-- parameter ever needs it.
local function unescape(value)
    return (value:gsub("%+", " "):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function query_value(request, key)
    local query = request:match("%?([^ ]*)") or ""
    for pair in query:gmatch("[^&]+") do
        local name, value = pair:match("^([^=]*)=(.*)$")
        if name == key then return unescape(value or "") end
    end
    return ""
end

local function ticket_path(ticket)
    if type(ticket) ~= "string" or not ticket:match("^%x+$") or #ticket ~= 32 then
        return nil
    end
    local file = TICKET_DIR .. "/" .. ticket
    local stored = fs.readfile(file)
    if not stored then return nil end
    local meta = fs.stat(file)
    if not meta or os.time() - (meta.mtime or 0) > TICKET_TTL then
        fs.unlink(file)
        return nil
    end
    return (stored:gsub("%s+$", ""))
end

local function respond(client, status, headers, length)
    client:send("HTTP/1.1 " .. status .. "\r\n")
    for name, value in pairs(headers) do
        client:send(name .. ": " .. value .. "\r\n")
    end
    client:send("Connection: close\r\n")
    if length then client:send("Content-Length: " .. length .. "\r\n") end
    client:send("\r\n")
end

local function serve(client)
    local request_line = ""
    local headers = {}
    local buffer = ""
    -- Read the head; mpv sends a small request, but be generous.
    while #buffer < 8192 do
        local chunk, err = client:recv(2048)
        if not chunk or #chunk == 0 then
            if err then return end
            break
        end
        buffer = buffer .. chunk
        if buffer:find("\r\n\r\n", 1, true) or buffer:find("\n\n", 1, true) then
            break
        end
    end
    request_line = buffer:match("^([^\r\n]*)") or ""
    for name, value in buffer:gmatch("([%w%-]+):%s*([^\r\n]*)") do
        headers[name:lower()] = value
    end

    local method, target = request_line:match("^(%u+)%s+(%S+)%s+HTTP")
    if not method then
        return respond(client, "400 Bad Request", {}, 0)
    end
    if method ~= "GET" and method ~= "HEAD" then
        return respond(client, "405 Method Not Allowed", {}, 0)
    end

    local path = ticket_path(query_value(target, "ticket"))
    if not path then
        return respond(client, "403 Forbidden", {}, 0)
    end
    local meta = fs.stat(path)
    if not meta or meta.type ~= "reg" then
        return respond(client, "404 Not Found", {}, 0)
    end

    local size = meta.size or 0
    local first, last = 0, size - 1
    local partial = false
    local range = headers["range"]
    if range then
        local from, to = range:match("^bytes=(%d+)%-(%d*)")
        if from then
            first = tonumber(from)
            last = to ~= "" and tonumber(to) or size - 1
            if first >= size or last < first then
                return respond(client, "416 Range Not Satisfiable",
                    {["Content-Range"] = "bytes */" .. size}, 0)
            end
            if last > size - 1 then last = size - 1 end
            partial = true
        end
    end

    local length = last - first + 1
    local response_headers = {
        ["Content-Type"] = mime_of(path),
        ["Accept-Ranges"] = "bytes",
        ["Cache-Control"] = "no-store"
    }
    if partial then
        response_headers["Content-Range"] =
            string.format("bytes %d-%d/%d", first, last, size)
    end
    respond(client, partial and "206 Partial Content" or "200 OK",
        response_headers, length)
    if method == "HEAD" then return end

    local input = io.open(path, "rb")
    if not input then return end
    if first > 0 then input:seek("set", first) end
    local remaining = length
    while remaining > 0 do
        local chunk = input:read(math.min(CHUNK, remaining))
        if not chunk or #chunk == 0 then break end
        local sent = client:send(chunk)
        if not sent then break end
        remaining = remaining - #chunk
    end
    input:close()
end

local server = nixio.socket("inet", "stream")
server:setsockopt("socket", "reuseaddr", 1)
if not server:bind(BIND_ADDR, PORT) then
    io.stderr:write("cannot bind " .. BIND_ADDR .. ":" .. PORT .. "\n")
    os.exit(1)
end
if not server:listen(16) then
    io.stderr:write("cannot listen\n")
    os.exit(1)
end

-- One child per connection: seeking opens several parallel ranged requests.
while true do
    local client = server:accept()
    if client then
        local pid = nixio.fork()
        if pid == 0 then
            server:close()
            local ok, err = pcall(serve, client)
            if not ok then io.stderr:write("stream error: " .. tostring(err) .. "\n") end
            pcall(function() client:close() end)
            os.exit(0)
        end
        client:close()
        -- Reap finished children without blocking the accept loop.
        while nixio.waitpid(-1, "nohang") do end
    end
end
