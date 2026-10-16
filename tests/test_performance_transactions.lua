-- Exact Lua 5.0.3 synchronous transaction regressions; no client or network.
local f=assert(io.open('test_individual_editor.lua'));local source=f:read('*a');f:close()
local cut=assert(string.find(source,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(source,1,cut-1)..'\nreturn boot'))()
local passes,failures=0,0
local function test(name,fn)
 local ok,why=pcall(fn);if ok then passes=passes+1;print('PASS '..name)else failures=failures+1;print('FAIL '..name..': '..tostring(why))end
end
local function fixture(bank)
 local p={entries={},denyRules={},setupRules={}}
 for i=1,39 do p.entries[i]={kind='normal',account='Alpha',class='mage',role='rdps',tier='t5r',spec='frost',race='gnome',gender='female'}end
 p.entries[40]={kind='player',charName='Tester',class='warrior',role='tank'}
 local db={presets={Full=p},currentPreset='Full',inviteCharacters={Alpha={name='Alpha',level=60,raidLicense='t5r',dungeonLicense='t5d',faction='Alliance'}}}
 for i=2,bank do db.presets['Bank '..i]={entries={{kind='player',charName='Tester',class='warrior',role='mdps'}},denyRules={},plannerPlayerSlot=40}end
 return db
end
local function counters(C)
 local n={migration=0,repair=0}
 local m,r=C.MigrateCharacterRoles,C.NormalizeBoardEntry
 C.MigrateCharacterRoles=function(...)n.migration=n.migration+1;return m(unpack(arg))end
 C.NormalizeBoardEntry=function(...)n.repair=n.repair+1;return r(unpack(arg))end
 return n
end
for _,bank in ipairs({1,100})do
 test('one normalization per 40-slot paint bank '..bank,function()
  local h=boot(fixture(bank));local C=h.C;local before=C.PlannerCopy(h:preset());local n=counters(C)
  h.env.RefreshComposition()
  assert(n.migration==1,'migration per paint: '..n.migration)
  assert(n.repair==40,'row repairs per paint: '..n.repair)
  assert(C.PlannerEqual(before,h:preset()),'paint changed valid plan')
  for i=1,10 do h.env.RefreshComposition()end
  assert(n.migration==11 and n.repair==440,'normalization is not bounded by paint count')
 end)
 test('one normalization per settings search bank '..bank,function()
  local h=boot(fixture(bank));h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Deny Rules'))
  local input
  for _,w in ipairs(h.frames)do if w.kind=='EditBox'and w:IsVisible()and w.scripts.OnTextChanged then input=w end end
  assert(input);local n=counters(h.C);input:SetText('f')
  assert(n.migration==1,'migration per search: '..n.migration)
  assert(n.repair==40,'row repairs per search: '..n.repair)
  input:SetText('');assert(n.migration==1,'blank search repaired data')
 end)
end
test('next paint revalidates in-place malformed data and role precedence',function()
 local h=boot(fixture(100));local db=h.env.ShirsRaidBuilderDB;local p=h:preset();local n=counters(h.C)
 p.entries[1]=false
 p.denyRules={false,{class='SHAMAN',role='MDPS',abilities={'Frost Shock','frost shock','  Frost Shock  '}}}
 h.env.RefreshComposition()
 assert(n.migration==1 and n.repair==40)
 assert(p.entries[1].kind=='empty','malformed row survived')
 assert(table.getn(p.denyRules)==1 and p.denyRules[1].class=='shaman'and table.getn(p.denyRules[1].abilities)==1,'deny repair skipped')
 assert(p.entries[40].role=='tank','library order replaced active player role')
 db.currentPreset='Bank 2';h.env.RefreshComposition()
 assert(n.migration==2 and n.repair==80,'selected-profile paint reused old validation')
 assert(h:preset().entries[40].kind=='player','new profile player placement failed')
end)
print('transaction tests: '..passes..' passed, '..failures..' failed');assert(failures==0)
