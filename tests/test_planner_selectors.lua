-- Composition selectors follow the server schema; no redundant class profiles.
local f=assert(io.open('test_individual_editor.lua')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function start()
 local db={currentPreset='Default',presets={Default={entries={},denyRules={},setupRules={}}},inviteCharacters={Alice={name='Alice',level=60,dungeonLicense='t5d',raidLicense='t5r',faction='Alliance'}}}
 local h=boot(db,'Alice'); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn); local p=h.C.plannerFrame
 h:click(h:button(p,'Composition')); return h,p
end

test('only Mage and Paladin get per-class spec controls; counts race and named profile stay',function()
 local h,p=start()
 for _,class in ipairs(h.C.PLANNER_CLASSES) do
  assert(p.classDefaults[class].raceButton:IsVisible(),'race selection removed')
  local spec=p.classDefaults[class].specButton
  if class=='mage' or class=='paladin' then assert(spec and spec:IsVisible())
  else assert(not spec or not spec:IsVisible(),'redundant profile for '..class) end
  for _,role in ipairs(h.C.PLANNER_ROLES) do if h.C.RoleAllowedForClass(class,role) then assert(p.countInputs[class..':'..role]:IsVisible(),'role/count control removed') end end
 end
 assert(p.nameInput:IsVisible() and h.env.ShirsRaidBuilderMainFrame,'named plan control removed')
 assert(table.concat(p.classDefaults.mage.specButton.options,',')=='auto,frost,fire,arcane')
 assert(table.concat(p.classDefaults.paladin.specButton.options,',')=='auto,might,magic')
end)

test('hidden stale class spec cannot block normal rows or invent command tokens',function()
 local h,p=start(); local C=h.C
 for _,class in ipairs(C.PLANNER_CLASSES) do
  for _,role in ipairs(C.PLANNER_ROLES) do if C.RoleAllowedForClass(class,role) then
   local faction=class=='shaman' and 'Horde' or 'Alliance'
   local source={name='Alice',chosenTier='t5r',faction=faction}
   local spec=(class=='mage' and 'fire') or (class=='paladin' and 'might') or 'fire'
   local e=assert(C.PlannerNormal(source,class,role,{race='auto',gender='female',defaults={[class]={spec=spec}}}),'stale hidden spec prevented '..class..':'..role)
   if class~='mage' and class~='paladin' or (class=='paladin' and role=='healer') then assert(e.spec=='default') end
   assert(C.BuildNormalHireCommand(e),'schema-valid row has no normal command: '..class..':'..role)
  end end
 end
end)

test('registered Mage and Paladin selectors retain meaningful concrete choices through build',function()
 local h,p=start(); local row=p.sourceRows[1]; row.normalCheck:SetChecked(1); h:fire(row.normalCheck,'OnClick')
 h:choose(p.classDefaults.mage.specButton,'fire'); h:choose(p.classDefaults.paladin.specButton,'magic')
 p.countInputs['mage:rdps']:SetText('1'); p.countInputs['paladin:tank']:SetText('1'); p.countInputs['paladin:healer']:SetText('1')
 h:click(p.buildButton); local r=assert(p.proposal,p.message:GetText())
 for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then
  if e.class=='mage' then assert(e.spec=='fire') elseif e.class=='paladin' and e.role=='tank' then assert(e.spec=='magic') else assert(e.spec=='default') end
 end end
end)
print("Shir's Raid Builder composition selectors tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('composition selector regressions failed') end
