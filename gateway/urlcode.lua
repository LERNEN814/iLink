-- Minimal URL encoding for names accepted by iLink's fixed routes.
local M = {}
function M.escape(value)
    return (tostring(value):gsub("([^%w%-%._~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end
function M.escape_path(value)
    return (tostring(value):gsub("([^%w%-%._~/])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end
return M
