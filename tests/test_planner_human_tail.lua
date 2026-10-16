-- Verified human tail is a generated-plan policy, never a live sort.
local f=assert(io.open('test_individual_editor.lua'));local t=f:read('*a');f:close();local at=assert(string.find(t,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(t,1,at-1)..'\nreturn boot'))()
local passed,failed=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then passed=passed+1;print('PASS '..n) else failed=failed+1;print('FAIL '..n..': '..tostring(e)) end end
local function dump(v)if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end;local out={};for k,x in pairs(v) do table.insert(out,'['..dump(k)..']='..dump(x)) end;table.sort(out);return '{'..table.concat(out,',')..'}' end
for _,number in ipairs({1,5,6,8}) do
 local n=number
 test(n..' verified humans reserve last group then overflow35 through registered lifecycle',function()
  local entries={};for i=1,n-1 do         local otherClass=i==1 and 'mage' or 'priest';local otherRole=i==1 and 'rdps' or 'healer';entries[i]={kind='player',charName='Human'..string.char(64+i),class=otherClass,role=otherRole} end
  local db={syncAccountId='1111111111111111',currentPreset='Default',presets={Default={entries=entries,denyRules={},setupRules={}}},inviteCharacters={}}
  for _,name in ipairs({'Alice','Bravo','Charlie','Delta','Echo','Foxtrot'}) do db.inviteCharacters[name]={name=name,level=60,dungeonLicense='t5d',raidLicense='t5r',faction='Alliance'} end
  local h=boot(db,'Alice');h.env.SetRaidSubgroup=function()error('must not live sort')end;h.env.SwapRaidSubgroup=h.env.SetRaidSubgroup
  h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);local p=h.C.plannerFrame
  for _,r in ipairs(p.sourceRows) do r.normalCheck:SetChecked(1);h:fire(r.normalCheck,'OnClick') end
  h:click(h:button(p,'Composition'));p.countInputs['mage:rdps']:SetText('10')
  assert(string.find(p.countSummary:GetText(),'Tanks 0 | Healers 0 | Melee DPS 0 | Ranged DPS 10',1,true),'Composition counted human roles')
  h:click(p.buildButton);local r=assert(p.proposal,p.message:GetText())
  assert(string.find(p.previewText:GetText(),'Tanks 0 | Healers 0 | Melee DPS 0 | Ranged DPS 10',1,true),'Proposed groups counted human roles')
  assert(r.total==10+n and r.player==n and r.normal==10 and r.plan.entries[40].charName=='Alice')
  for i=1,n-1 do assert(r.plan.entries[40-i].charName=='Human'..string.char(64+i),'human identity order/tail changed') end
  for i=1,10 do assert(r.plan.entries[i].kind=='normal','companions not packed before human tail') end
  for i=11,40-n do assert(not h.C.IsFilledEntry(r.plan.entries[i]),'hole not before tail') end
  local expected=dump(r.plan.entries);p.nameInput:SetText('Human tail');h:click(p.applyButton);h.env.RefreshComposition();assert(dump(h:preset().entries)==expected)
  local fresh=boot(assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))(),'Alice');assert(dump(fresh:preset().entries)==expected)
  fresh:click(fresh.env.ShirsRaidBuilderMainFrame.plannerBtn);fresh:click(fresh.C.plannerFrame.buildButton);assert(dump(assert(fresh.C.plannerFrame.proposal).plan.entries)==expected)
 end)
end
test('six humans block rightmost Shaman35 without overwrite and explain safe next slot',function()
 local h=boot({presets={}},'Alice');local C=h.C;local e={};for i=1,5 do e[i]={kind='player',charName='Human'..string.char(64+i),class='mage',role='rdps'} end
 for i=1,7 do e[10+i]={kind='legacy',sourceName='Support'..string.char(64+i),charName='Support'..string.char(64+i),class='shaman',role='healer'} end
 -- Six humans fill35..40; Group7 rightmost35 belongs to a human.
 local r=assert(C.PlannerBuild({entries=e},{},{counts={},sources={},player={name='Alice',class='warrior',role='tank'}}))
 assert(r.plan.entries[35].kind=='player' and r.plan.entries[34].class=='shaman');assert(string.find(table.concat(r.notes,' '),'35',1,true))
end)
test('unknown companion is not silently reclassified as a human and invalid human identity fails',function()
 local h=boot({presets={}},'Alice');local C=h.C
 local bad=C.PlannerBuild({entries={{kind='player',charName='???',class='priest',role='healer'}}},{},{counts={},sources={},player={name='Alice',class='warrior',role='tank'}});assert(not bad,'unknown human accepted')
 local guest={kind='guest',charName='Companion',companionName='Companion',class='mage',role='rdps'}
 local r=assert(C.PlannerBuild({entries={[12]=guest}},{},{counts={},sources={},player={name='Alice',class='warrior',role='tank'}}));assert(r.plan.entries[12].kind=='guest' and r.plan.entries[39].kind~='player','unverified guest became human')
end)
print("Shir's Raid Builder human tail tests: "..(failed==0 and 'PASS' or 'FAIL')..' ('..passed..' passed, '..failed..' failed)');assert(failed==0,'human tail regressions failed')
