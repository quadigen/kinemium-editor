local fs=require("@lune/fs")
local luau=require("@lune/luau")
local r=require("@lune/roblox")
local Instance,Vector3,CFrame,UDim2=r.Instance,r.Vector3,r.CFrame,r.UDim2
local fixture, imported, calls, deferred=nil,nil,0,{}
local UI={create=function(class,props,parent)
 assert(props.InputSink==false and props.Active==false)
 local obj=Instance.new(class)
 for k,v in props do
  if k~="InputSink" and k~="Shadows" and k~="PostProcessing" and k~="UpdateRate" then obj[k]=v end
 end
 obj.Parent=parent
 return obj
end}
local preview=luau.load(fs.readFile("internal/kine_preview.luau"),{environment={
 require=function() return UI end,
 game={GetService=function() return {ImportFile=function(_,path) calls+=1;imported=fixture();return imported end} end},
 Instance=Instance,Vector3=Vector3,CFrame=CFrame,Color3=r.Color3,
 task={defer=function(fn) table.insert(deferred,fn) end,wait=function() end},
}})()
local function run(factory,aspect,expected)
 fixture=factory
 local holder=Instance.new("Folder")
 local parent=Instance.new("Frame");parent.Parent=holder
 local fallback={Parent=parent,Position=UDim2.fromOffset(2,2),Size=UDim2.fromOffset(60,38),AbsoluteSize=r.Vector2.new(60*aspect,60),Visible=true}
 preview.Attach(parent,"model.KINE",fallback)
 table.remove(deferred,1)()
 local frame=parent:FindFirstChild("KineThumbnail")
 assert((frame~=nil)==expected)
 if frame then
  assert(fallback.Visible==false and imported.Parent==frame)
  local camera=frame.CurrentCamera
  for _,part in frame:GetDescendants() do
   assert(not part:IsA("LuaSourceContainer"))
   if part:IsA("BasePart") then
    for x=-1,1,2 do for y=-1,1,2 do for z=-1,1,2 do
     local p=camera.CFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(part.Size*r.Vector3.new(x,y,z)*0.5))
     local vertical=math.tan(math.rad(camera.FieldOfView)/2)
     assert(-p.Z>0.05)
     assert(math.abs(p.Y)/(-p.Z*vertical)<1)
     assert(math.abs(p.X)/(-p.Z*vertical*aspect)<1)
    end end end
   end
  end
 else assert(fallback.Visible) end
 holder:Destroy()
end
run(function() local p=Instance.new("Part");p.Size=Vector3.new(2,80,4);p.CFrame=CFrame.new(500,20,-40)*CFrame.Angles(0.4,0.7,0.2);return p end,60/38,true)
run(function()
 local m=Instance.new("Model")
 for i=1,3 do local p=Instance.new("Part");p.Size=Vector3.new(i*8,2,3);p.CFrame=CFrame.new(i*15,30,-50)*CFrame.Angles(i,0.4,0.7);p.Parent=m end
 local script=Instance.new("Script");script.Parent=m
 return m
end,0.4,true)
run(function() return Instance.new("Model") end,1,false)
run(function() return Instance.new("Folder") end,1,false)
run(function() error("invalid file") end,1,false)
local parent=Instance.new("Frame")
local fallback={Parent=parent}
preview.Attach(parent,"stale.kine",fallback)
parent:Destroy()
local before=calls
table.remove(deferred,1)()
assert(calls==before)
print("KINE_PREVIEW_TEST_PASSED: rotated part, model, narrow aspect, script removal, invalid/unsupported files, stale jobs")
