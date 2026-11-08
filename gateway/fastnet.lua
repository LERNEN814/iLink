-- FastNet proxy: fixed endpoints, buffered result.
-- The router runs FastNet's web service on 127.0.0.1:3200; the phone never
-- talks to it directly and no caller-supplied path or query reaches it.
local json = require "luci.jsonc"
local nixio = require "nixio"
local M = {}

local HOST, PORT = "127.0.0.1", 3200
local MAX_BODY = 512 * 1024
local KEEP_LOGS = 40

local routes = {
    quick = "/api/quick/stream",
    nat = "/api/nat",
    ipv6 = "/api/ipv6/stream"
}

local function read_stream(path, timeout)
    local socket = nixio.connect(HOST, PORT)
    if not socket then error("FastNet is not reachable") end
    socket:setopt("socket", "rcvtimeo", timeout)
    socket:setopt("socket", "sndtimeo", 5)
    local request = table.concat({
        "GET " .. path .. " HTTP/1.1\r\n",
        "Host: 127.0.0.1\r\n",
        "Accept: text/event-stream, application/json\r\n",
        "Connection: close\r\n\r\n"
    })
    if not socket:send(request) then socket:close(); error("FastNet write failed") end
    local chunks, total = {}, 0
    while true do
        local chunk = socket:recv(16384)
        if not chunk or #chunk == 0 then break end
        total = total + #chunk
        if total > MAX_BODY then socket:close(); error("FastNet response too large") end
        chunks[#chunks + 1] = chunk
    end
    socket:close()
    local raw = table.concat(chunks)
    local header, body = raw:match("^(.-)\r\n\r\n(.*)$")
    if not header then error("invalid FastNet response") end
    local code = tonumber(header:match("^HTTP/%d%.%d%s+(%d+)"))
    if not code or code < 200 or code >= 300 then error("FastNet request failed") end
    if header:lower():find("transfer%-encoding:%s*chunked") then
        local decoded, position = {}, 1
        while true do
            local _, stop, size_text = body:find("^(%x+)[^\r\n]*\r\n", position)
            if not stop then break end
            local size = tonumber(size_text, 16)
            position = stop + 1
            if size == 0 then break end
            decoded[#decoded + 1] = body:sub(position, position + size - 1)
            position = position + size + 2
        end
        body = table.concat(decoded)
    end
    return body
end

local function parse_sse(raw)
    local summary, stages, logs = {}, {}, {}
    -- /api/nat answers with plain JSON; the others stream SSE.
    if raw:match("^%s*{") then
        local ok, value = pcall(json.parse, raw)
        if ok and type(value) == "table" then
            local output = value.output
            value.output = nil
            if type(output) == "string" and output ~= "" then
                for line in output:gmatch("[^%c]+") do logs[#logs + 1] = line end
            end
            return { summary = value, stages = stages, logs = logs }
        end
    end
    local event
    for line in raw:gmatch("[^\r\n]+") do
        local name = line:match("^event:%s*(.*)$")
        if name then
            event = name
        else
            local data = line:match("^data:%s?(.*)$")
            if data then
                if event == "log" then
                    logs[#logs + 1] = data
                elseif event == "progress" or event == "summary" or event == "stage" then
                    local ok, value = pcall(json.parse, data)
                    if ok and type(value) == "table" then
                        if event == "stage" then
                            stages[#stages + 1] = value
                        else
                            for key, item in pairs(value) do summary[key] = item end
                        end
                    end
                elseif event == "error" then
                    summary.error = data
                end
            end
        end
    end
    if #logs > KEEP_LOGS then
        local tail = {}
        for index = #logs - KEEP_LOGS + 1, #logs do tail[#tail + 1] = logs[index] end
        logs = tail
    end
    return { summary = summary, stages = stages, logs = logs }
end

function M.quick() return parse_sse(read_stream(routes.quick, 90)) end
function M.nat() return parse_sse(read_stream(routes.nat, 45)) end
function M.ipv6() return parse_sse(read_stream(routes.ipv6, 45)) end

M.routes = routes
return M
