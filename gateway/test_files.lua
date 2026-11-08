local root = "/mnt/data_sdb1"
local tree = {
    [root] = { type = "dir", entries = { "docs", "note.txt", "escape" } },
    [root .. "/docs"] = { type = "dir", entries = {} },
    [root .. "/note.txt"] = { type = "reg", size = 5 },
    [root .. "/escape"] = { type = "lnk" }
}

package.preload["nixio.fs"] = function()
    return {
        realpath = function(path)
            if path == root .. "/escape" then return "/etc" end
            return tree[path] and path or nil
        end,
        readlink = function(path) return tree[path] and tree[path].type == "lnk" and "/etc" or nil end,
        stat = function(path) return tree[path] end,
        dir = function(path)
            local values = tree[path].entries
            local index = 0
            return function() index = index + 1; return values[index] end
        end,
        basename = function(path) return path:match("([^/]+)$") end,
        dirname = function(path) return path:match("^(.*)/[^/]+$") end,
        mkdir = function(path)
            tree[path] = { type = "dir", entries = {} }
            table.insert(tree[root].entries, "new")
            return true
        end,
        rename = function(source, target)
            tree[target] = tree[source]
            tree[source] = nil
            return true
        end,
        rmdir = function(path)
            if #tree[path].entries > 0 then return nil end
            tree[path] = nil
            return true
        end,
        unlink = function(path) tree[path] = nil; return true end
    }
end
package.preload["luci.sys"] = function()
    return { exec = function(command)
        assert(command:find("/usr/bin/base64", 1, true))
        assert(command:find("renamed.txt", 1, true))
        return "aGVsbG8="
    end }
end

local files = require "files"
local listed = files.list({ path = "" })
assert(#listed.entries == 2, "symlink entries must be hidden")
assert(listed.entries[1].directory)
assert(files.mkdir({ path = "", name = "new" }).created)
assert(files.rename({ path = "note.txt", name = "renamed.txt" }).renamed)
assert(files.download({ path = "renamed.txt" }).base64 == "aGVsbG8=")
assert(files.remove({ path = "new" }).deleted)
for _, path in ipairs({ "../etc", "/etc", "docs/../../etc", "docs\\windows", "escape", "missing" }) do
    assert(not pcall(files.list, { path = path }), "unsafe path accepted: " .. path)
end
assert(not pcall(files.mkdir, { path = "", name = "../escape" }))
assert(not pcall(files.remove, { path = "" }))
print("File path isolation, safe mutations and Base64 download tests: OK")
