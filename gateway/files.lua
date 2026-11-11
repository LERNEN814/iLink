-- Restricted file operations: canonical paths only, no path or symlink escape.
local fs = require "nixio.fs"
local sys = require "luci.sys"
local M = {}

local ROOT = "/mnt/data_sdb1"
local MAX_READ = 32 * 1024 * 1024
local MAX_PREVIEW_TEXT = 256 * 1024
local MAX_PREVIEW_IMAGE = 8 * 1024 * 1024

-- Streaming: raw bytes with Range support for the built-in media player and
-- uncapped downloads. Tickets keep long-lived device credentials out of the
-- player process.
local TICKET_DIR = "/tmp/ilink-stream-tickets"
local TICKET_TTL = 900
local STREAM_CHUNK = 65536
local media_types = {
    mp4 = "video/mp4", mkv = "video/x-matroska", avi = "video/x-msvideo",
    mov = "video/quicktime", webm = "video/webm", flv = "video/x-flv",
    ts = "video/mp2t", ["m3u8"] = "application/vnd.apple.mpegurl",
    mp3 = "audio/mpeg", flac = "audio/flac", aac = "audio/aac",
    m4a = "audio/mp4", wav = "audio/x-wav", opus = "audio/opus",
    ogg = "audio/ogg", oga = "audio/ogg"
}

local function canonical(relative, must_exist)
    if type(relative) ~= "string" or #relative > 1024 or relative:find("%z") or
        relative:find("[\r\n]") or relative:find("\\") or relative:find("%.%.") or
        relative:find("^/") or relative:find("/$") then
        error("invalid path")
    end
    if relative == "" or relative == "/" then relative = "." end
    if relative:find("^%./") then relative = relative:sub(3) end
    local requested = relative == "." and ROOT or ROOT .. "/" .. relative
    if fs.readlink(requested) then error("symbolic links are not supported") end
    local real = fs.realpath(requested)
    if not real then
        if must_exist ~= false then error("path not found") end
        local parent = fs.realpath(fs.dirname(requested))
        if not parent then error("parent not found") end
        real = parent .. "/" .. fs.basename(relative)
    end
    if real ~= ROOT and real:sub(1, #ROOT + 1) ~= ROOT .. "/" then
        error("path outside shared directory")
    end
    if fs.readlink(real) then error("symbolic links are not supported") end
    return real, relative == "." and "" or relative
end

local function entry(path, relative)
    if fs.readlink(path) then return nil end
    local stat = fs.stat(path)
    if not stat then return nil end
    return {
        name = fs.basename(path),
        path = relative,
        directory = stat.type == "dir",
        size = stat.size or 0,
        modified = stat.mtime or 0
    }
end

function M.list(body)
    local directory, relative = canonical(body.path or "")
    local directory_stat = fs.stat(directory)
    if not directory_stat or directory_stat.type ~= "dir" then error("not a directory") end
    local result = {}
    for name in fs.dir(directory) do
        if name ~= "." and name ~= ".." and #name <= 255 then
            local item_relative = relative == "" and name or relative .. "/" .. name
            local item = entry(directory .. "/" .. name, item_relative)
            if item then result[#result + 1] = item end
        end
    end
    table.sort(result, function(a, b)
        if a.directory ~= b.directory then return a.directory end
        return a.name:lower() < b.name:lower()
    end)
    return { path = relative, entries = result }
end

local function valid_name(value)
    return type(value) == "string" and #value > 0 and #value <= 255 and
        not value:find("[/\\]") and not value:find("%z") and
        value ~= "." and value ~= ".." and not value:find("[\r\n]")
end

function M.mkdir(body)
    local parent = canonical(body.path or "")
    if not valid_name(body.name) then error("invalid directory name") end
    local target = parent .. "/" .. body.name
    if fs.stat(target) or fs.readlink(target) then error("already exists") end
    if not fs.mkdir(target, "0755") then error("create directory failed") end
    return { created = true }
end

function M.rename(body)
    local source, relative = canonical(body.path)
    if relative == "" or not valid_name(body.name) then error("invalid rename") end
    local target = fs.dirname(source) .. "/" .. body.name
    if fs.stat(target) or fs.readlink(target) then error("already exists") end
    if not fs.rename(source, target) then error("rename failed") end
    return { renamed = true }
end

function M.remove(body)
    local source, relative = canonical(body.path)
    if relative == "" then error("cannot delete shared directory") end
    local stat = fs.stat(source)
    local ok
    if stat.type == "dir" then ok = fs.rmdir(source) else ok = fs.unlink(source) end
    if not ok then error("delete failed; directory may not be empty") end
    return { deleted = true }
end

local image_types = {
    png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg",
    gif = "image/gif", webp = "image/webp", bmp = "image/bmp"
}

local function extension_of(name)
    return (name:match("%.([%w]+)$") or ""):lower()
end

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local temp_counter = 0

local function temp_path(suffix)
    temp_counter = temp_counter + 1
    return "/tmp/ilink-file-" .. tostring(os.time()) .. "-" ..
        tostring(temp_counter) .. suffix
end

-- openssl ships with iStoreOS; /usr/bin/base64 does not exist on this system.
local function encode_file(path)
    local out = temp_path(".b64")
    sys.exec("/usr/bin/openssl base64 -A -in " .. shell_quote(path) ..
        " -out " .. shell_quote(out))
    local encoded = fs.readfile(out) or ""
    fs.unlink(out)
    return (encoded:gsub("%s+", ""))
end

local function decode_to(encoded, target)
    local staged = temp_path(".b64")
    if not fs.writefile(staged, encoded) then error("cannot stage upload") end
    sys.exec("/usr/bin/openssl base64 -d -A -in " .. shell_quote(staged) ..
        " -out " .. shell_quote(target))
    fs.unlink(staged)
end

function M.download(body)
    local source = canonical(body.path)
    local stat = fs.stat(source)
    if stat.type ~= "reg" or stat.size > MAX_READ then error("file too large or unsupported") end
    -- Fixed executable and canonical, quoted path; never a caller-supplied command.
    local encoded = encode_file(source)
    if encoded == "" and stat.size > 0 then error("read failed") end
    return { name = fs.basename(source), size = stat.size, base64 = encoded }
end

-- A short-lived, path-locked credential so the media player never holds the
-- device token. Expired tickets are swept on every issue.
function M.stream_ticket(body)
    local source = canonical(body.path)
    local stat = fs.stat(source)
    if stat.type ~= "reg" then error("not a file") end
    fs.mkdirr(TICKET_DIR)
    local now = os.time()
    for name in fs.dir(TICKET_DIR) do
        local path = TICKET_DIR .. "/" .. name
        local meta = fs.stat(path)
        if meta and now - (meta.mtime or 0) > TICKET_TTL then fs.unlink(path) end
    end
    local handle = io.popen("cat /proc/sys/kernel/random/uuid 2>/dev/null")
    local ticket = handle and (handle:read("*l") or "") or ""
    if handle then handle:close() end
    ticket = ticket:gsub("%-", "")
    if #ticket ~= 32 then error("cannot create stream ticket") end
    if not fs.writefile(TICKET_DIR .. "/" .. ticket, source) then
        error("cannot store stream ticket")
    end
    return { ticket = ticket, expires = now + TICKET_TTL }
end

-- Confirms a ticket still matches the requested path; the dispatcher has
-- already verified the caller by ticket or device token.
function M.stream_path(ticket, requested)
    if type(ticket) ~= "string" or not ticket:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") then
        error("invalid ticket")
    end
    local file = TICKET_DIR .. "/" .. ticket
    local stored = fs.readfile(file)
    if not stored then error("unknown ticket") end
    local meta = fs.stat(file)
    if not meta or os.time() - (meta.mtime or 0) > TICKET_TTL then
        fs.unlink(file)
        error("ticket expired")
    end
    local source = stored:gsub("%s+$", "")
    if requested ~= "" and requested ~= source then error("ticket path mismatch") end
    return source
end

-- Raw byte response with HTTP Range support; binary-safe chunked io.
-- Control characters come from string.char so shell heredocs can never
-- corrupt the escapes again.
function M.stream_raw(env)
    local send = type(uhttpd) == "table" and uhttpd.send or io.write
    local raw_path = env.STREAM_PATH or ""
    local source
    if raw_path:sub(1, 1) == "/" then
        -- Absolute form only arrives from a validated stream ticket, which
        -- stores canonical paths; still refuse traversal characters. Plain
        -- finds only: NUL inside a Lua pattern breaks the parser.
        local clean = true
        for i = 1, #raw_path do
            local byte = raw_path:byte(i)
            if byte == 0 or byte == 13 or byte == 10 or byte == 92 then
                clean = false
                break
            end
        end
        if not clean or raw_path:find("..", 1, true) then
            error("invalid path")
        end
        source = raw_path
    else
        source = canonical(raw_path)
    end
    local stat = fs.stat(source)
    if not stat or stat.type ~= "reg" then
        send("Status: 404 Not Found\r\nContent-Length: 0\r\n\r\n")
        return
    end
    local size = stat.size or 0
    local start_pos, end_pos = 0, size - 1
    local partial = false
    local from, to = (env.HTTP_RANGE or ""):match("^bytes=(%d+)%-(%d*)$")
    if from then
        start_pos = tonumber(from)
        end_pos = to ~= "" and tonumber(to) or size - 1
        if start_pos >= size or end_pos < start_pos then
            send("Status: 416 Range Not Satisfiable\r\n")
            send("Content-Range: bytes */" .. size .. "\r\n")
            send("Content-Length: 0\r\n\r\n")
            return
        end
        end_pos = math.min(end_pos, size - 1)
        partial = true
    end
    local mime = media_types[extension_of(source)] or "application/octet-stream"
    local length = end_pos - start_pos + 1
    send("Status: " .. (partial and "206 Partial Content" or "200 OK") .. "\r\n")
    send("Content-Type: " .. mime .. "\r\n")
    send("Accept-Ranges: bytes\r\n")
    send("Cache-Control: no-store\r\n")
    if partial then
        send("Content-Range: bytes " .. start_pos .. "-" .. end_pos .. "/" .. size .. "\r\n")
    end
    send("Content-Length: " .. length .. "\r\n\r\n")
    if env.REQUEST_METHOD == "HEAD" then return end
    local input = io.open(source, "rb")
    if not input then return end
    if start_pos > 0 then input:seek("set", start_pos) end
    local remaining = length
    while remaining > 0 do
        local chunk = input:read(math.min(STREAM_CHUNK, remaining))
        if not chunk or #chunk == 0 then break end
        send(chunk)
        remaining = remaining - #chunk
    end
    input:close()
end

function M.copy(body)
    local source = canonical(body.path)
    local destination = canonical(body.destination or "")
    local stat = fs.stat(source)
    local target = destination .. "/" ..
        (body.name and valid_name(body.name) and body.name or fs.basename(source))
    if fs.stat(target) or fs.readlink(target) then error("already exists") end
    if stat.type == "dir" then error("directory copy is not supported") end
    if stat.size > MAX_READ then error("file too large to copy") end
    local content = fs.readfile(source)
    if not content then error("open failed") end
    if not fs.writefile(target, content) then error("copy failed") end
    return { copied = true }
end

function M.move(body)
    local source = canonical(body.path)
    if source == ROOT then error("cannot move the shared directory") end
    local destination = canonical(body.destination or "")
    local target = destination .. "/" ..
        (body.name and valid_name(body.name) and body.name or fs.basename(source))
    if fs.stat(target) or fs.readlink(target) then error("already exists") end
    if not fs.rename(source, target) then error("move failed") end
    return { moved = true }
end

function M.preview(body)
    local source = canonical(body.path)
    local stat = fs.stat(source)
    if stat.type ~= "reg" then error("not a file") end
    local mime = image_types[extension_of(source)]
    if mime then
        if stat.size > MAX_PREVIEW_IMAGE then error("image too large") end
        local encoded = encode_file(source)
        if encoded == "" and stat.size > 0 then error("read failed") end
        return { kind = "image", mime = mime, base64 = encoded }
    end
    if stat.size > MAX_PREVIEW_TEXT then error("text too large") end
    local content = fs.readfile(source)
    if not content then error("open failed") end
    if content:find("%z") then
        return { kind = "binary", size = stat.size }
    end
    return { kind = "text", content = content, size = stat.size }
end

function M.upload(body)
    local directory = canonical(body.path or "")
    if not valid_name(body.name) then error("invalid file name") end
    if type(body.base64) ~= "string" or #body.base64 == 0 then
        error("empty upload")
    end
    -- Base64 is 4/3 of the payload; reject before decoding.
    if #body.base64 > MAX_READ * 2 then error("file too large") end
    local target = directory .. "/" .. body.name
    if fs.readlink(target) then error("symbolic links are not supported") end
    if fs.stat(target) and body.overwrite ~= true then error("already exists") end
    if body.overwrite == true then fs.unlink(target) end
    decode_to(body.base64, target)
    local stat = fs.stat(target)
    if not stat or stat.size == 0 then error("upload failed") end
    return { uploaded = true, size = stat.size }
end

M.canonical = canonical
return M
