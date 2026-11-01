local fs = require("@lune/fs")
local luau = require("@lune/luau")
for _, path in {"internal/files.luau", "internal/kine_preview.luau"} do
 luau.load(fs.readFile(path))
 print("PARSE PASSED",path)
end
