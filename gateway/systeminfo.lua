-- Service states and package updates: read-only views behind fixed names.
local sys = require "luci.sys"
local M = {}

-- id is the init script, process is what actually shows up in the process table.
local SERVICES = {
    { id = "openclash", process = "clash", label = "OpenClash" },
    { id = "alist", process = "alist", label = "AList" },
    { id = "aria2", process = "aria2c", label = "Aria2" },
    { id = "qbittorrent", process = "qbittorrent-nox", label = "qBittorrent" },
    { id = "fastnet", process = "FastNet", label = "FastNet" },
    { id = "ddnsto", process = "ddnsto", label = "DDNSTO" }
}

function M.services()
    local result = {}
    for _, service in ipairs(SERVICES) do
        local code = sys.call("pidof " .. service.process .. " >/dev/null 2>&1")
        result[#result + 1] = {
            id = service.id,
            label = service.label,
            running = code == 0
        }
    end
    return { services = result }
end

local function helper(name, arguments)
    local connection = require("ubus").connect()
    if not connection then error("ubus unavailable") end
    local result, code = connection:call("ilink-action", name, arguments or {})
    connection:close()
    if not result or (code and code ~= 0) then error("helper rejected the request") end
    return result
end

function M.traffic()
    return helper("traffic", { sample = false })
end

function M.exec(body)
    local command = type(body) == "table" and tostring(body.command or "") or ""
    if command == "" then error("empty command") end
    return helper("exec", { command = command })
end

-- iStoreOS publishes no online firmware API, so the closest stable signal is
-- whether the vendor feed carries newer base-system packages.
function M.firmware()
    local releaseText = sys.exec(
        ". /etc/openwrt_release 2>/dev/null; echo \"$DISTRIB_RELEASE\"; echo \"$DISTRIB_TARGET\"; echo \"$DISTRIB_DESCRIPTION\""
    ) or ""
    local release, target, description = releaseText:match("([^%c]*)%c+([^%c]*)%c+([^%c]*)")
    local kernel = (sys.exec("uname -r") or ""):gsub("%s+$", "")
    local available = {}
    for line in (sys.exec("/bin/opkg list-upgradable 2>/dev/null") or ""):gmatch("[^%c]+") do
        local name = line:match("^(%S+)%s+%-")
        if name and name:match("^[%w%.%+_%-]+$") and name ~= "Multiple" then
            available[#available + 1] = name
        end
        if #available > 60 then break end
    end
    table.sort(available)
    return {
        release = release ~= "" and release or "unknown",
        description = description or "",
        target = target or "",
        kernel = kernel,
        available = available,
        count = #available
    }
end

function M.upgrade()
    return helper("upgrade")
end

function M.upgrade_status()
    return helper("upgrade-status")
end

function M.updates()
    -- opkg needs root; the ACL-gated helper runs the same read-only query.
    local connection = require("ubus").connect()
    if connection then
        local result, code = connection:call("ilink-action", "updates", {})
        connection:close()
        if result and (not code or code == 0) and type(result.packages) == "table" then
            return result
        end
    end
    local handle = io.popen("/bin/opkg list-upgradable 2>/dev/null")
    local names = {}
    if handle then
        for line in handle:lines() do
            local name = line:match("^(%S+)%s")
            if name then names[#names + 1] = name end
            if #names > 200 then break end
        end
        handle:close()
    end
    table.sort(names)
    return { count = #names, packages = names }
end

return M
