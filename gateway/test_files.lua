local root = "/mnt/data_sdb1"
local tree = {
    [root] = { type = "dir", entries = { "docs", "note.txt", "escape" } },
    [root .. "/docs"] = { type = "dir", entries = {} },
    [root .. "/note.txt"] = { type = "reg", size = 5, content = "hello" },
    [root .. "/escape"] = { type = "lnk" }
}

local function parent_of(path) return path:match("^(.*)/[^/]+$") end
local function name_of(path) return path:match("([^/]+)$") end

package.preload["nixio.fs"] = function()
    return {
        realpath = function(path)
            if path == root .. "/escape" then return "/etc" end
            return tree[path] and path or nil
        end,
        readlink = function(path)
            return tree[path] and tree[path].type == "lnk" and "/etc" or nil
        end,
        stat = function(path) return tree[path] end,
        dir = function(path)
            local values = tree[path].entries
            local index = 0
            return function()
                index = index + 1
                return values[index]
            end
        end,
        basename = name_of,
        dirname = parent_of,
        mkdir = function(path)
            tree[path] = { type = "dir", entries = {} }
            table.insert(tree[parent_of(path)].entries, name_of(path))
            return true
        end,
        rename = function(source, target)
            local parent = parent_of(target)
            if tree[parent] then
                table.insert(tree[parent].entries, name_of(target))
            end
            tree[target] = tree[source]
            tree[source] = nil
            return true
        end,
        rmdir = function(path)
            if #tree[path].entries > 0 then return nil end
            tree[path] = nil
            return true
        end,
        unlink = function(path) tree[path] = nil; return true end,
        readfile = function(path)
            return tree[path] and tree[path].content or nil
        end,
        writefile = function(path, data)
            tree[path] = { type = "reg", size = #data, content = data }
            return true
        end
    }
end

-- /usr/bin/base64 does not exist on iStoreOS; the module uses openssl instead.
local decode_mode = false
package.preload["luci.sys"] = function()
    return { exec = function(command)
        assert(command:find("^/usr/bin/openssl base64"), "unexpected tool: " .. command)
        local target = command:match("%-out '([^']+)'")
        assert(target, "missing output path")
        decode_mode = command:find(" -d ", 1, true) ~= nil
        -- Emulate the tool: encode writes base64, decode writes the payload.
        tree[target] = decode_mode
            and { type = "reg", size = 5, content = "hello" }
            or { type = "reg", size = 8, content = "aGVsbG8=" }
        return ""
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

-- Copy and move stay inside the shared directory.
assert(files.copy({ path = "renamed.txt", destination = "", name = "copy.txt" }).copied)
tree[root .. "/big.bin"] = { type = "reg", size = 40 * 1024 * 1024 }
assert(not pcall(files.copy, { path = "big.bin", destination = "" }), "oversized copy must be refused")
assert(tree[root .. "/copy.txt"].content == "hello")
assert(files.move({ path = "copy.txt", destination = "docs" }).moved)
assert(tree[root .. "/docs/copy.txt"] ~= nil and tree[root .. "/copy.txt"] == nil)

-- Preview returns text for a text file.
local preview = files.preview({ path = "docs/copy.txt" })
assert(preview.kind == "text" and preview.content == "hello")

-- Upload decodes into the target and refuses to overwrite silently.
local uploaded = files.upload({ path = "", name = "payload.txt", base64 = "aGVsbG8=" })
assert(uploaded.uploaded and uploaded.size == 5)
assert(tree[root .. "/payload.txt"].content == "hello")
assert(not pcall(files.upload, { path = "", name = "payload.txt", base64 = "aGVsbG8=" }))
assert(files.upload({ path = "", name = "payload.txt", base64 = "aGVsbG8=", overwrite = true }).uploaded)

for _, path in ipairs({ "../etc", "/etc", "docs/../../etc", "docs\\windows", "escape", "missing" }) do
    assert(not pcall(files.list, { path = path }), "unsafe path accepted: " .. path)
end
assert(not pcall(files.mkdir, { path = "", name = "../escape" }))
assert(not pcall(files.remove, { path = "" }))
assert(not pcall(files.upload, { path = "", name = "../evil", base64 = "aGk=" }))
assert(not pcall(files.copy, { path = "renamed.txt", destination = "../etc" }))
assert(not pcall(files.move, { path = "docs/copy.txt", destination = "/etc" }))

local original_exec = package.loaded["luci.sys"].exec
package.loaded["luci.sys"].exec = function(command)
    original_exec(command)
    return ""
end
assert(decode_mode, "upload must use the decoder")

print("File path isolation, copy/move, upload, preview tests: OK")
