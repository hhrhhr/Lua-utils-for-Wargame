local in_file = assert(arg[1], "[ERR ] no arguments")
local out_dir = arg[2] or "."

require("util_binary_reader")
local reader = BinaryReader

reader:open(in_file)
print("[LOG ] open " .. in_file)

reader:idstring("edat")

local header = {}
header.version      = reader:uint32()   -- 1-EE, 2-AB
header.hash_v1      = {}
for i = 1, 4 do
    table.insert(header.hash_v1, reader:hex32())
end
reader:uint8()  -- skip 0x00
header.dir_offset   = reader:uint32()
header.dir_size     = reader:uint32()
header.file_offset  = reader:uint32()
header.file_size    = reader:uint32()
header.unk          = reader:uint32()   -- 0x00 0x00 0x00 0x00
header.block_size   = reader:uint32()
header.hash_v2      = {}
for i = 1, 4 do
    table.insert(header.hash_v2, reader:hex32())
end

local pathgen = {}
local path = {}
local files = {}

reader:seek(header.dir_offset)
local dir_end = header.dir_offset + header.dir_size

while reader:pos() < dir_end do
    local entry_idx = reader:uint32()
    local entry_size = reader:uint32()

    if entry_idx > 0 then
        if entry_size > 0 then
            table.insert(pathgen, reader:pos() + entry_size - 8)
        elseif #pathgen > 0 then
            table.insert(pathgen, pathgen[#pathgen])
        end

        local entry_name = reader:str()
        table.insert(path, entry_name)

        if (reader:pos() % 2) == 0 then
            reader:uint8()
        end

    elseif entry_idx == 0 then
        local t = {}

        t.offset = reader:uint32() + header.file_offset
        if header.version == 2 then
            tmp = reader:uint32()
        end

        t.size = reader:uint32()
        if header.version == 2 then
            tmp = reader:uint32()
        end

        if header.version == 1 then
            tmp = reader:uint8()
        else
            t.hash = {}
            for i = 1, 4 do
                table.insert(t.hash, reader:hex32())
            end
        end

        local filename = reader:str()
        t.filename = {}
        tmp = table.concat(path) .. filename
        for s in string.gmatch(tmp, "[^\\]+") do
            table.insert(t.filename, s)
        end
        table.insert(files, t)

        if (reader:pos() % 2) == 0 then
            reader:uint8()
        end

        local path_pos = reader:pos()
        while #pathgen > 0 and path_pos == pathgen[#pathgen] do
            table.remove(path)
            table.remove(pathgen)
        end
    end
end

print("[LOG ] found " .. #files .. " files")


-- prepare directory's listing
-- collect all unique paths
local dirs = {}
for k, v in ipairs(files) do
    local d = table.concat(v.filename, "\\", 1, #v.filename-1)
    if not dirs[d] then
        dirs[d] = true
    end
end

-- sort list
local dirs_sorted = {}
for k, v in pairs(dirs) do
    table.insert(dirs_sorted, k)
end
table.sort(dirs_sorted)

-- make unique directories tree
dirs = {}
for k, v in ipairs(dirs_sorted) do
    local dir = {}
    for s in string.gmatch(v, "[^\\]+") do
        table.insert(dir, s)
    end
    for i = 1, #dir do
        local str = ""
        str = table.concat(dir, "\\", 1, i)
        if not dirs[str] then
            dirs[str] = true
        end
    end
end

-- sort list again
dirs_sorted = {}
for k, v in pairs(dirs) do
    table.insert(dirs_sorted, k)
end
table.sort(dirs_sorted)


-- make directories
print("[LOG ] start making " .. #dirs_sorted .. " directories")

local ffi = require("ffi")
ffi.cdef[[
int _mkdir(const char *path);
char * strerror (int errnum);
]]

local is_err = true
for k, v in ipairs(dirs_sorted) do
    local dir = out_dir .. "\\" .. v
    local err = ffi.C._mkdir(dir)
    if err ~= 0 then
        local errno = ffi.errno()
        -- '(17) file exists' is OK
        if errno ~= 17 then
            local errno_str = ffi.string(ffi.C.strerror(errno))
            print("[ERR ] mkdir failed, errno (" .. errno .. "): " .. errno_str)
            break
        end
    end
    is_err = false
end

-- unpack
if not is_err then
    print("[LOG ] start unpacking")
    local writer
    for k, v in ipairs(files) do
        local fullpath = out_dir .. "\\" .. table.concat(v.filename, "\\")
        io.write(".")
        local w = assert(io.open(fullpath, "w+b"))
        reader:seek(v.offset)
        local data = reader:str(v.size)
        w:write(data)
        w:close()
    end
    print()
end

reader:close()
print("[LOG ] close " .. in_file)
