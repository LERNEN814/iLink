-- Downloader bridge: torrents go to qBittorrent, video links to yt-dlp.
-- Reuses the binaries the existing Telegram bot already relies on; that bot
-- and its state are not touched.
local json = require "luci.jsonc"
local nixio = require "nixio"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local M = {}

local QB = { host = "127.0.0.1", port = 8080 }
local YTDLP = "/mnt/data_sdb1/bin/yt-dlp"
local VIDEO_DIR = "/mnt/data_sdb1/video"
local JOBS = "/tmp/ilink-dl"
local MAX_URL = 2048

local shell_quote = require("ilink_util").shell_quote

local function http(port, method, path, body, extra)
    local socket = nixio.connect("127.0.0.1", port)
    if not socket then return nil, "unreachable" end
    socket:setopt("socket", "rcvtimeo", 15)
    socket:setopt("socket", "sndtimeo", 10)
    local head = {
        method .. " " .. path .. " HTTP/1.1\r\n",
        "Host: 127.0.0.1\r\n"
    }
    for name, value in pairs(extra or {}) do
        head[#head + 1] = name .. ": " .. value .. "\r\n"
    end
    head[#head + 1] = "Content-Length: " .. #(body or "") .. "\r\n"
    head[#head + 1] = "Connection: close\r\n\r\n"
    if not socket:send(table.concat(head) .. (body or "")) then
        socket:close()
        return nil, "write failed"
    end
    local chunks = {}
    while true do
        local chunk = socket:recv(16384)
        if not chunk or #chunk == 0 then break end
        chunks[#chunks + 1] = chunk
    end
    socket:close()
    local raw = table.concat(chunks)
    local header, payload = raw:match("^(.-)\r\n\r\n(.*)$")
    if not header then return nil, "invalid response" end
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

local function classify(url)
    if not url:match("^https?://") and not url:match("^magnet:%?") then
        error("only http(s) links and magnets are supported")
    end
    if url:match("^magnet:%?") then return "torrent" end
    local path = url:match("^https?://[^/]+([^?#]*)") or ""
    if path:lower():match("%.torrent$") then return "torrent" end
    return "video"
end

local function qb_add(url)
    local code, body = http(QB.port, "POST", "/api/v2/torrents/add",
        "urls=" .. url:gsub("([^%w%-%._~:/%?%%=&%+])", function(c)
            return string.format("%%%02X", c:byte())
        end),
        { ["Content-Type"] = "application/x-www-form-urlencoded" })
    if code ~= 200 then error("qBittorrent rejected the torrent") end
    if body and body:lower():find("fails") then
        error("qBittorrent could not add the torrent")
    end
    return true
end

local function job_id()
    return tostring(os.time()) .. "-" .. tostring(math.random(100000))
end

local function start_video(url)
    if not fs.stat(YTDLP) then error("yt-dlp is not installed") end
    if fs.stat(VIDEO_DIR, "type") ~= "dir" then fs.mkdirr(VIDEO_DIR) end
    fs.mkdirr(JOBS)
    local id = job_id()
    local log = JOBS .. "/" .. id .. ".log"
    local pid = JOBS .. "/" .. id .. ".pid"
    local runner = JOBS .. "/" .. id .. ".sh"
    fs.writefile(JOBS .. "/" .. id .. ".meta",
        json.stringify({ url = url, started = os.time() }))
    -- A fixed runner file keeps the URL out of any shell command line.
    local nl = string.char(10)
    local body = "#!/bin/sh" .. nl
    body = body .. "echo $$ > " .. shell_quote(pid) .. nl
    body = body .. "exec " .. shell_quote(YTDLP)
    body = body .. " -f 'b[protocol^=http]/b' --no-mtime -o "
    body = body .. shell_quote(VIDEO_DIR .. "/%(title).180B.%(ext)s")
    body = body .. " " .. shell_quote(url) .. nl
    fs.writefile(runner, body)
    -- Detached: the request returns at once and the Telegram bot is untouched.
    sys.call("setsid /bin/sh " .. shell_quote(runner) ..
        " >> " .. shell_quote(log) .. " 2>&1 &")
    return id
end

local function last_lines(path, limit)
    local handle = io.open(path, "rb")
    if not handle then return {} end
    local lines = {}
    for line in handle:lines() do
        lines[#lines + 1] = line
        if #lines > limit * 2 then
            table.remove(lines, 1)
        end
    end
    handle:close()
    local tail = {}
    for index = math.max(1, #lines - limit + 1), #lines do
        tail[#tail + 1] = lines[index]
    end
    return tail
end

local function video_jobs()
    local result = {}
    local handle = io.popen("ls -1t " .. JOBS .. "/*.meta 2>/dev/null | head -12", "r")
    if not handle then return result end
    local current = os.time()
    for path in handle:lines() do
        local raw = fs.readfile(path) or ""
        local meta = json.parse(raw) or {}
        local base = path:gsub("%.meta$", "")
        local log = base .. ".log"
        local lines = last_lines(log, 4)
        local text = table.concat(lines, " ")
        local status = "running"
        if text:find("has already been downloaded", 1, true) or
            text:find("100%% of", 1, true) then
            status = "done"
        elseif text:find("ERROR", 1, true) then
            status = "error"
        elseif current - (tonumber(meta.started) or current) > 7200 then
            status = "stale"
        end
        result[#result + 1] = {
            id = fs.basename(base),
            url = meta.url,
            started = meta.started,
            status = status,
            progress = text:match("(%d+%.%d+)%%"),
            tail = lines
        }
    end
    handle:close()
    return result
end

local function torrents()
    local code, body = http(QB.port, "GET", "/api/v2/torrents/info")
    if code ~= 200 or not body then return {} end
    local parsed = json.parse(body)
    if type(parsed) ~= "table" then return {} end
    local result = {}
    for _, item in ipairs(parsed) do
        result[#result + 1] = {
            hash = item.hash,
            name = item.name,
            size = item.size,
            progress = item.progress,
            speed = item.dlspeed,
            state = item.state,
            eta = item.eta
        }
    end
    return result
end

function M.submit(body)
    local url = body.url
    if type(url) ~= "string" then error("missing url") end
    url = url:gsub("^%s+", ""):gsub("%s+$", "")
    if #url == 0 or #url > MAX_URL or url:find("[%s\"]") then
        error("invalid url")
    end
    local kind = classify(url)
    if kind == "torrent" then
        qb_add(url)
        return { kind = "torrent" }
    end
    return { kind = "video", id = start_video(url) }
end

function M.jobs()
    return { torrents = torrents(), videos = video_jobs() }
end

function M.remove(body)
    if body.kind == "torrent" then
        local hash = body.id
        if type(hash) ~= "string" or not hash:match("^[%x]+$") then
            error("invalid torrent id")
        end
        http(QB.port, "POST", "/api/v2/torrents/delete",
            "hashes=" .. hash .. "&deleteFiles=false",
            { ["Content-Type"] = "application/x-www-form-urlencoded" })
        return { removed = true }
    end
    local id = body.id
    if type(id) ~= "string" or not id:match("^[%d%-]+$") then
        error("invalid job id")
    end
    local pid = (fs.readfile(JOBS .. "/" .. id .. ".pid") or ""):gsub("%s+", "")
    if pid:match("^%d+$") then sys.call("kill " .. pid .. " 2>/dev/null") end
    fs.unlink(JOBS .. "/" .. id .. ".meta")
    fs.unlink(JOBS .. "/" .. id .. ".pid")
    return { removed = true }
end

return M
