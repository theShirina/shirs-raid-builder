-- Target MCP exposes Dwarf Paladin; preferences are not performance claims.
local f=assert(io.open('test_individual_editor.lua'));local src=f:read('*a');f:close()
local boundary=assert(string.find(src,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(src,1,boundary-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local function open(h)
 h.C.OpenPlanner();local p=h.C.plannerFrame
 for _,row in ipairs(p.sourceRows) do if row.source and row.source.name=='Tester' then row.normalCheck:SetChecked(1);h:fire(row.normalCheck,'OnClick') end end
 return p
end
local preferred={{'Alliance','warrior','tank','human'},{'Alliance','warrior','mdps','human'},{'Alliance','mage','rdps','gnome'},{'Alliance','warlock','rdps','gnome'},{'Alliance','priest','healer','dwarf'},{'Alliance','paladin','healer','dwarf'},{'Alliance','hunter','rdps','nightelf'},{'Alliance','druid','healer','nightelf'},{'Alliance','rogue','mdps','human'},{'Horde','warrior','tank','undead'},{'Horde','warrior','mdps','orc'},{'Horde','warlock','rdps','orc'},{'Horde','mage','rdps','troll'},{'Horde','shaman','healer','troll'},{'Horde','hunter','rdps','troll'},{'Horde','rogue','mdps','troll'}}
local function database(faction)
 return {currentPreset='Default',presets={Default={entries={},denyRules={},setupRules={}}},inviteCharacters={Tester={name='Tester',level=60,dungeonLicense='t2d',raidLicense='t3r',faction=faction}}}
end
test('every requested faction class role has a valid deterministic preferred race',function()
 local h=boot(database('Alliance'));local C=h.C
 for _,v in ipairs(preferred) do local row=assert(C.PlannerNormal({name='Source',faction=v[1],chosenTier='t3r'},v[2],v[3],{gender='female'}));assert(row.race==v[4],table.concat(v,':'));assert(C.BuildNormalHireCommand(row)) end
 assert(C.PlannerNormal({name='Source',faction='Alliance',chosenTier='t3r'},'priest','rdps',{}).race=='human','unspecified Shadow race was guessed')
 assert(not C.PlannerNormal({name='Source',faction='Horde',chosenTier='t3r'},'paladin','healer',{}),'wrong faction generated')
 assert(not C.PlannerNormal({name='Source',faction='Alliance',chosenTier='t3r'},'mage','rdps',{defaults={mage={race='dwarf'}}}),'invalid class race generated')
end)
test('class manual choices and independent Warrior tank override survive reopen and reload',function()
 local h=boot(database('Horde'));local C=h.C;h.env.UnitFactionGroup=function() return 'Horde' end
 local p=open(h);C.PlannerTab('counts')
 assert(p.classDefaults.warrior.tankRaceButton,'Tank race override unavailable')
 h:choose(p.classDefaults.warrior.raceButton,'orc');h:choose(p.classDefaults.warrior.tankRaceButton,'troll')
 p.countInputs['warrior:tank']:SetText('1');p.countInputs['warrior:mdps']:SetText('1');h:click(p.buildButton)
 local r=assert(p.proposal,p.message:GetText());for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.race==(e.role=='tank' and 'troll' or 'orc')) end end
 p.nameInput:SetText('Races');h:click(p.applyButton);h.env.RefreshComposition();local saved=C.PlannerCopy(h.env.ShirsRaidBuilderDB)
 C.OpenPlanner();p=C.plannerFrame;assert(p.request.defaults.warrior.race=='orc' and p.request.defaults.warrior.roles.tank=='troll')
 local fresh=boot(saved);fresh.env.UnitFactionGroup=function() return 'Horde' end;fresh.C.OpenPlanner();local p2=fresh.C.plannerFrame
 assert(p2.request.defaults.warrior.race=='orc' and p2.request.defaults.warrior.roles.tank=='troll','manual race lost on fresh load')
 for _,e in ipairs(fresh:preset().entries) do if e.kind=='normal' then assert(e.race==(e.role=='tank' and 'troll' or 'orc'));assert(fresh.C.BuildNormalHireCommand(e)) end end
end)
test('captured manual race and legacy identity stay unchanged while missing defaults use preferences',function()
 local db=database('Alliance');db.presets.Default.entries={{kind='normal',account='Tester',class='mage',role='rdps',tier='t3r',race='human',gender='female',spec='fire'},{kind='legacy',sourceName='Oldmage',charName='Oldmage',class='mage',role='rdps',race='human',spec='fire',whisperName='Oldmag-lite'}}
 local h=boot(db);local before=h.C.PlannerCopy(h:preset().entries[2]);local p=open(h)
 h:click(p.buildButton);local r=assert(p.proposal,p.message:GetText());for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then assert(e.race=='human','captured manual race changed') elseif e.kind=='legacy' then assert(h.C.PlannerEqual(e,before),'legacy identity changed') end end
 h.C.ClosePlanner();h.C.OpenPlanner();p=h.C.plannerFrame;h.C.PlannerTab('counts');h:choose(p.classDefaults.mage.raceButton,'gnome');h:click(p.buildButton)
 for _,e in ipairs(assert(p.proposal).plan.entries) do if e.kind=='normal' then assert(e.race=='gnome') end end
end)
test('mixed captured races survive and only an additional normal uses the missing preferred default',function()
 local db=database('Alliance');db.presets.Default.entries={
  {kind='normal',account='Tester',class='mage',role='rdps',tier='t3r',race='human',gender='female',spec='frost'},
  {kind='normal',account='Tester',class='mage',role='rdps',tier='t3r',race='gnome',gender='female',spec='frost'}}
 local h=boot(db);local p=open(h);p.countInputs['mage:rdps']:SetText('3');h:click(p.buildButton)
 local races={};for _,e in ipairs(assert(p.proposal,p.message:GetText()).plan.entries) do if e.kind=='normal' then table.insert(races,e.race) end end;table.sort(races)
 assert(table.concat(races,',')=='gnome,gnome,human','captured races replaced by new defaults')
end)
test('all preferred choices pass registered Build Create Preview queue reopen and fresh Lua',function()
 for _,v in ipairs(preferred) do
  local h=boot(database(v[1]));h.env.UnitFactionGroup=function() return v[1] end;local p=open(h)
  p.countInputs[v[2]..':'..v[3]]:SetText('1');h:click(p.buildButton);local r=assert(p.proposal,p.message:GetText());local found
  for _,e in ipairs(r.plan.entries) do if e.kind=='normal' then found=e;assert(e.race==v[4],table.concat(v,':')) end end
  assert(found);local before=h.C.PlannerCopy(r.plan.entries);p.nameInput:SetText('Preferred');h:click(p.applyButton);h.env.RefreshComposition();assert(h.C.PlannerEqual(h:preset().entries,before))
  local queue=h.C.BuildQueue(h:preset());local command=h.C.BuildNormalHireCommand(found);local has=false
  for _,step in ipairs(queue) do if step.command==command then has=true end end
  assert(has and command and string.find(command,v[4],1,true),'preferred race lost before paid boundary')
  local fresh=boot(h.C.PlannerCopy(h.env.ShirsRaidBuilderDB));fresh.env.UnitFactionGroup=function() return v[1] end
  fresh.C.OpenPlanner();fresh:click(fresh.C.plannerFrame.buildButton);assert(fresh.C.PlannerEqual(fresh.C.plannerFrame.proposal.plan.entries,before),'fresh rebuild changed preferred choice')
 end
end)
test('malformed saved race settings sanitize without granting invalid class faction choices',function()
 local h=boot(database('Alliance'));local C=h.C
 for _,value in ipairs({true,12,'bad'}) do
  local d=C.PlannerRaceDefaults({entries={}},{raceDefaults=value});assert(d.mage.race=='auto')
 end
 local d=C.PlannerRaceDefaults({entries={}},{raceDefaults={mage={race='dwarf',roles={rdps='dwarf'}},warrior={race='orc',roles='bad'}}})
 assert(d.mage.race=='auto' and not d.mage.roles.rdps)
 assert(not C.PlannerNormal({name='Source',faction='Alliance',chosenTier='t3r'},'warrior','tank',{defaults=d}),'wrong-faction saved race was silently replaced')
end)
print("Shir's Raid Builder race default tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'race preference regressions failed')
