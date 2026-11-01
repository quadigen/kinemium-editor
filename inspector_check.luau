local fs=require('@lune/fs')
local luau=require('@lune/luau')
for _,path in {'internal/inspector.luau','internal/Components/input.luau','internal/Components/dropdown.luau'} do luau.load(fs.readFile(path));print('PARSE PASSED',path) end
