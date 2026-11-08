-- Restricted file operations: canonical paths only, no path or symlink escape.
local fs = require "nixio.fs"
local sys = require "luci.sys"
local M = {}

local ROOT = "/mnt/data_sdb1"
local MAX_READ = 32 * 1024 * 1024

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

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.download(body)
    local source = canonical(body.path)
    local stat = fs.stat(source)
    if stat.type ~= "reg" or stat.size > MAX_READ then error("file too large or unsupported") end
    -- Fixed executable and canonical, quoted path; never a caller-supplied command.
    local encoded = sys.exec("/usr/bin/base64 -w0 -- " .. shell_quote(source))
    if encoded == "" and stat.size > 0 then error("read failed") end
    return { name = fs.basename(source), size = stat.size, base64 = encoded }
end

M.canonical = canonical
return M
