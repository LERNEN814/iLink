-- Minimal URL encoding for names accepted by iLink's fixed routes.
local M = {}
function M.escape(value)
    return (tostring(value):gsub("([^%w%-%._~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end
-- Form decoding: spaces first, then percent escapes, so a literal + that
-- arrived as %2B survives.
function M.unescape(value)
    return (tostring(value or ""):gsub("%+", " "):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- One value out of a raw query string.
function M.query_value(raw, key)
    for pair in tostring(raw or ""):gmatch("[^&]+") do
        local name, value = pair:match("^([^=]*)=(.*)$")
        if name == key then return M.unescape(value) end
    end
    return ""
end

function M.escape_path(value)
    return (tostring(value):gsub("([^%w%-%._~/])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end
return M
