-- Helpers shared by the gateway modules. Kept in one file so the same quoting,
-- staging and name rules are not re-implemented per module.
local fs = require "nixio.fs"
local sys = require "luci.sys"
local M = {}

local counter = 0

function M.shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.temp_path(prefix, suffix)
    counter = counter + 1
    return "/tmp/ilink-" .. prefix .. "-" .. tostring(os.time()) .. "-" ..
        tostring(counter) .. (suffix or "")
end

function M.valid_name(value)
    return type(value) == "string" and #value > 0 and #value <= 128 and
        not value:find("/") and not value:find("\\") and not value:find("%.%.") and
        value ~= "." and value ~= ".."
end

-- openssl ships with iStoreOS; /usr/bin/base64 does not exist on this system.
function M.encode_file(path)
    return sys.exec("/usr/bin/openssl base64 -A -in " .. M.shell_quote(path) .. " 2>/dev/null") or ""
end

function M.decode_to(encoded, target)
    local staged = M.temp_path("b64", ".b64")
    if not fs.writefile(staged, encoded) then error("cannot stage upload") end
    sys.exec("/usr/bin/openssl base64 -d -A -in " .. M.shell_quote(staged) ..
        " -out " .. M.shell_quote(target))
    fs.unlink(staged)
end

-- Content types the media player and the browser care about.
M.mime_types = {
    mp4 = "video/mp4", mkv = "video/x-matroska", avi = "video/x-msvideo",
    mov = "video/quicktime", webm = "video/webm", flv = "video/x-flv",
    ts = "video/mp2t", ["m3u8"] = "application/vnd.apple.mpegurl",
    mp3 = "audio/mpeg", flac = "audio/flac", aac = "audio/aac",
    m4a = "audio/mp4", wav = "audio/x-wav", opus = "audio/opus",
    ogg = "audio/ogg", oga = "audio/ogg"
}

function M.mime_of(path)
    local extension = path:match("%.([%w]+)$")
    return extension and M.mime_types[extension:lower()] or
        "application/octet-stream"
end

return M
