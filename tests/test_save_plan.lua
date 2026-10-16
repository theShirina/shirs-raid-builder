-- Registered Vanilla save handlers, exact Lua 5.0.3. Synthetic UI/quotes only.
local f=assert(io.open('test_individual_editor.lua'));local text=f:read('*a');f:close()
local at=assert(string.find(text,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..name)else fail=fail+1;print('FAIL '..name..': '..tostring(e))end end
local function copy(v)if type(v)~='table'then return v end;local t={};for k,x in pairs(v)do t[k]=copy(x)end;return t end
local function dump(v)
 if type(v)~='table'then return type(v)=='string'and string.format('%q',v)or tostring(v)end
 local keys,p={},{};for k in pairs(v)do table.insert(keys,k)end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 for _,k in ipairs(keys)do table.insert(p,'['..dump(k)..']='..dump(v[k]))end;return '{'..table.concat(p,',')..'}'
end
local function start(extra)
 local db={currentPreset='Original',syncAccountId='1111111111111111',quietMode=false,presets={Original={entries={
  {kind='normal',account='Alice',tier='t5r',class='warrior',role='tank',spec='default',race='human',gender='female'},
  {kind='normal',account='Alice',tier='t5r',class='warrior',role='tank',spec='default',race='human',gender='female'},
  {kind='normal',account='Alice',tier='t5r',class='warrior',role='tank',spec='default',race='human',gender='female'},
  {kind='normal',account='Alice',tier='t5r',class='warrior',role='tank',spec='default',race='human',gender='female'},
  {kind='normal',account='Bravo',tier='t5r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'},
  {kind='normal',account='Bravo',tier='t5r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'},
  {kind='normal',account='Carol',tier='t4r',class='paladin',role='healer',spec='default',race='dwarf',gender='female'},
  {kind='legacy',sourceName='Longlegacy',charName='Longlegacy',whisperName='Longleg-lite',class='mage',role='rdps',spec='fire',denyList={'Frostbolt'},setupRules={{class='mage',key='armor',value='mage',scope='individual',target='Longleg-lite'}}},
  {kind='guest',companionName='Human',class='priest',role='healer'},
  [40]={kind='player',charName='Alice',class='warrior',role='tank'}},
  plannerPlayerSlot=40,metadata={label='Keep exact metadata',nested={1,false,'value'}},
  denyRules={{class='mage',role='rdps',abilities={'Frostbolt'}}},setupRules={}}},
  inviteCharacters={Alice={name='Alice',level=60,raidLicense='t5r',dungeonLicense='t5d',faction='Alliance'},Bravo={name='Bravo',level=60,raidLicense='t5r',dungeonLicense='t5d',faction='Alliance'},Carol={name='Carol',level=60,raidLicense='t4r',dungeonLicense='t4d',faction='Alliance'}}}
 for i=1,extra or 0 do db.presets['Other '..i]=copy(db.presets.Original)end
 local h=boot(db,'Alice');h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);local p=h.C.plannerFrame
 for _,row in ipairs(p.sourceRows)do row.normalCheck:SetChecked(1);h:fire(row.normalCheck,'OnClick')end
 h:click(h:button(p,'Tier priority'));h:choose(p.priorityMode,'Custom')
 h:click(h:button(p,'Composition'));p.ultraGoldCheck:SetChecked(1);h:fire(p.ultraGoldCheck,'OnClick')
 h:click(p.buildButton);assert(p.proposal,p.message:GetText());assert(p.proposal.normal==7 and p.proposal.player==1 and p.proposal.guest==1 and p.proposal.legacy==1)
 return h,p
end
local function forbiddenSaveWork(h)
 local counts={}
 for _,name in ipairs({'PlannerBuild','PlannerUltraApply','PlannerUltraReassign','PlannerAllocate','PlannerGroup','PlannerQuoteStart','QuoteStartBatch'})do
  local fn=h.C[name];if fn then local key=name;h.C[name]=function(...)counts[key]=(counts[key]or 0)+1;return fn(unpack(arg))end end
 end
 return function()for name,n in pairs(counts)do assert(n==0,'save reran '..name..' ('..n..' call(s))')end end
end

test('Create saves the exact reviewed plan without rebuilding or querying',function()
 local h,p=start();local expected=copy(p.proposal.plan);local original=copy(h:preset());local check=forbiddenSaveWork(h)
 p.nameInput:SetText('New saved plan');h:click(p.applyButton)
 assert(not p:IsShown() and h.env.ShirsRaidBuilderDB.currentPreset=='New saved plan',p.message:GetText())
 assert(h.C.PlannerEqual(expected,h:preset()) and h.C.PlannerEqual(original,h.env.ShirsRaidBuilderDB.presets.Original),'save changed the reviewed or original plan')
 check()
end)

test('overwrite warning repeat and Cancel do no planning or writes; Replace saves once',function()
 local h,p=start(100);local expected=copy(p.proposal.plan);local db=h.env.ShirsRaidBuilderDB;local before=dump(db);local selected=copy(p.request.sources);local check=forbiddenSaveWork(h)
 p.replaceCheck:SetChecked(1);h:fire(p.replaceCheck,'OnClick')
 for i=1,3 do
  h:click(p.applyButton);assert(p.confirmFrame:IsShown() and string.find(p.confirmText:GetText(),'Original',1,true),'named overwrite warning missing')
  assert(dump(db)==before,'warning wrote data');h:click(h:button(p.confirmFrame,'Cancel'));assert(dump(db)==before and p:IsShown() and p.proposal,'Cancel changed draft or data')
 end
 h:click(p.applyButton);h:click(h:button(p.confirmFrame,'Replace'));check()
 assert(db==h.env.ShirsRaidBuilderDB and db.currentPreset=='Original' and h.C.PlannerEqual(expected,h:preset()),'confirmed exact plan or bound global lost')
 local n=0;for _ in pairs(db.presets)do n=n+1 end;assert(n==101,'overwrite added a duplicate profile')
 h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);assert(h.C.PlannerEqual(selected,p.request.sources) and p.request.ultraGold and p.request.priorityMode=='custom','choices changed after Save')
end)

test('saved data survives serialization into a fresh Core and UI with no shared tables',function()
 local h,p=start();local expected=copy(p.proposal.plan);local original=copy(h:preset());p.nameInput:SetText('Roundtrip');h:click(p.applyButton)
 local db=h.env.ShirsRaidBuilderDB;local re=boot(assert(loadstring('return '..dump(db)))(),'Alice')
 assert(re.C.PlannerEqual(expected,re:preset()) and re.C.PlannerEqual(original,re.env.ShirsRaidBuilderDB.presets.Original),'fresh load changed slots/source/tier/legacy/human/metadata')
 re:click(re.env.ShirsRaidBuilderMainFrame.plannerBtn);local rp=re.C.plannerFrame
 assert(rp.request.ultraGold and rp.request.priorityMode=='custom' and re.C.PlannerEqual(p.request.customOrder,rp.request.customOrder),'settings lost after fresh load')
end)

for _,name in ipairs({'','   ','Original','Bad/name'})do local value=name
 test('invalid or duplicate create name preserves all data: '..value,function()
  local h,p=start();local before=dump(h.env.ShirsRaidBuilderDB);local check=forbiddenSaveWork(h)
  p.nameInput:SetText(value);h:click(p.applyButton);check();assert(p:IsShown() and p.proposal and before==dump(h.env.ShirsRaidBuilderDB) and p.message:GetText()~='','invalid name changed data')
 end)
end

test('Rename keeps slash names exact; a rejected planner name never rekeys the saved profile',function()
 local h,p=start();p.nameInput:SetText('First');h:click(p.applyButton);local main=h.env.ShirsRaidBuilderMainFrame
 h:click(h:button(main,'Rename'));local prompt=h.env.ShirsRaidBuilderNamePrompt;prompt.input:SetText('Raid / slash');local plan=h:preset();h:click(h:button(prompt,'Save'))
 local db=h.env.ShirsRaidBuilderDB;assert(db.currentPreset=='Raid / slash' and db.presets['Raid / slash']==plan and not db.presets.First,'Rename normalized the saved name')
 h:click(main.plannerBtn);p=h.C.plannerFrame;h:click(p.buildButton);assert(p.proposal)
 p.replaceCheck:SetChecked(1);h:fire(p.replaceCheck,'OnClick');local before=dump(db);local check=forbiddenSaveWork(h);h:click(p.applyButton);check()
 assert(before==dump(db) and not p.confirmFrame:IsShown(),'existing invalid PlanName behavior changed or slash profile disappeared')
end)

for _,offset in ipairs({-1,31})do local age=offset
 test('expired or future price context can Save the unchanged reviewed plan: '..age,function()
  local h,p=start();local expected=copy(p.proposal.plan);local check=forbiddenSaveWork(h);h.env.GetTime=function()return 100+age end
  p.nameInput:SetText('Stale');h:click(p.applyButton);check();assert(h.env.ShirsRaidBuilderDB.currentPreset=='Stale' and h.C.PlannerEqual(expected,h:preset()),'unchanged reviewed plan could not save')
 end)
end

test('quote expiry while overwrite warning is open permits exact confirmed Save',function()
 local h,p=start();local expected=copy(p.proposal.plan);p.replaceCheck:SetChecked(1);h:fire(p.replaceCheck,'OnClick');h:click(p.applyButton);local check=forbiddenSaveWork(h)
 h.env.GetTime=function()return 131 end;h:click(h:button(p.confirmFrame,'Replace'));check();assert(h.C.PlannerEqual(expected,h:preset())and not p.confirmFrame:IsShown()and not p:IsShown())
end)

local requestChanges={
 counts=function(q)q.counts['mage:rdps']=3 end,
 composition=function(q)q.counts['priest:healer']=1 end,
 source=function(q)q.sources['own:alice'].selected=false end,
 tier=function(q)q.sources['own:alice'].tier='t4r' end,
 race=function(q)q.defaults.warrior.race='dwarf' end,
 roleRace=function(q)q.defaults.warrior.roles.tank='dwarf' end,
 capturedRace=function(q)q.defaults.warrior.captured['alice:tank'][1]='dwarf' end,
 spec=function(q)q.defaults.mage.spec='frost' end,
 gender=function(q)q.gender='male' end,
 customOrder=function(q)q.customOrder[1],q.customOrder[2]=q.customOrder[2],q.customOrder[1]end,
 priority=function(q)q.priorityMode='auto' end,
 ultra=function(q)q.ultraGold=false end,
 saveGold=function(q)q.saveGold=not q.saveGold end,
 price=function(q)q.quotes['own:alice'].base=999 end,
 discount=function(q)q.quotes['own:alice'].ex=777 end,
 mask=function(q)q.quotes['own:alice'].mask='1' end,
 quoteCount=function(q)q.quotes['own:alice'].count=1 end,
 quoteTier=function(q)q.quotes['own:alice'].tier='t4r' end,
 quoteIdentity=function(q)q.quotes['own:alice'].accountId='2222222222222222'end,
 quoteTime=function(q)q.quotes['own:alice'].received=101 end,
}
for key,change in pairs(requestChanges)do local key,change=key,change
 test('changed complete draft input rejects Save without recomputing: '..key,function()
  local h,p=start();local before=dump(h.env.ShirsRaidBuilderDB);local check=forbiddenSaveWork(h);change(p.request);p.nameInput:SetText('Must not save');h:click(p.applyButton);check()
  assert(before==dump(h.env.ShirsRaidBuilderDB) and not p.proposal,'changed request used a stale proposal')
 end)
end

local sourceChanges={
 key=function(s)s.key='changed' end,name=function(s)s.name='Other' end,owner=function(s)s.accountId='2222222222222222'end,
 endpoint=function(s)s.endpoint='Other'end,localSource=function(s)s.localSource=false end,
 faction=function(s)s.faction='Horde'end,capacity=function(s)s.capacity=3 end,conflict=function(s)s.conflict=true end,
 eligibility=function(s)s.eligible=false end,tier=function(s)s.tiers={'t0d'}end,
 level=function(s)s.record.level=59 end,count=function(s)s.record.count=1 end,max=function(s)s.record.maxCount=3 end,
 licence=function(s)s.record.raidLicense='t4r'end,legacyClass=function(s)s.legacyClass='priest'end,legacyRole=function(s)s.legacyRole='healer'end,
}
for key,change in pairs(sourceChanges)do local key,change=key,change
 test('changed current selected source rejects Save: '..key,function()
  local h,p=start();local read=h.C.PlannerReadSources;h.C.PlannerReadSources=function()local sources=copy(read());for _,s in ipairs(sources)do if s.key=='own:alice'then change(s)end end;return sources end
  local before=dump(h.env.ShirsRaidBuilderDB);local check=forbiddenSaveWork(h);p.nameInput:SetText('Must not save');h:click(p.applyButton);check()
  assert(before==dump(h.env.ShirsRaidBuilderDB) and not p.proposal,'changed source used a stale proposal')
 end)
end

test('advisory observation age can change without rerunning Build or extending quote freshness',function()
 local h,p=start();local read=h.C.PlannerReadSources;h.C.PlannerReadSources=function()local rows=copy(read());for _,s in ipairs(rows)do s.received=999;s.freshness='different label';s.live=not s.live;s.record.observed=999 end;return rows end
 local expected=copy(p.proposal.plan);local check=forbiddenSaveWork(h);p.nameInput:SetText('Age only');h:click(p.applyButton);check();assert(h.C.PlannerEqual(expected,h:preset())and not p:IsShown(),p.message:GetText())
end)

for _,which in ipairs({'proposal','base','selection','busy','missing receipt'})do local which=which
 test('changed proposal or context cannot Save: '..which,function()
  local h,p=start();local db=h.env.ShirsRaidBuilderDB
  if which=='proposal'then p.proposal.plan.entries[1].tier='t0d'
  elseif which=='base'then h:preset().metadata.label='Changed'
  elseif which=='selection'then db.currentPreset='Other';db.presets.Other=copy(h:preset())
  elseif which=='busy'then h.C.handAuthority='busy'
  else p.saveCheck=nil end
  local before=dump(db);local check=forbiddenSaveWork(h);p.nameInput:SetText('Must not save');h:click(p.applyButton);check();assert(before==dump(db),'invalid context saved')
 end)
end

test('replaced SavedVariable account/global cannot receive a proposal from the previous binding',function()
 local h,p=start();local replacement=copy(h.env.ShirsRaidBuilderDB);h.env.ShirsRaidBuilderDB=replacement;local before=dump(replacement);local check=forbiddenSaveWork(h)
 p.nameInput:SetText('Wrong binding');h:click(p.applyButton);check();assert(before==dump(replacement),'proposal crossed a replaced account/global binding')
end)

test('a failed source read cannot partially create or overwrite a profile',function()
 local h,p=start();local before=dump(h.env.ShirsRaidBuilderDB);local check=forbiddenSaveWork(h);p.nameInput:SetText('Error case');h.C.PlannerReadSources=function()error('synthetic read failure')end
 local ok,e=pcall(function()h:click(p.applyButton)end);check();assert(not ok and string.find(e,'synthetic read failure',1,true)and before==dump(h.env.ShirsRaidBuilderDB))
end)

test('repeated confirmed overwrites keep one selected profile and the exact proposal',function()
 local h,p=start();local db=h.env.ShirsRaidBuilderDB;local bankCount=0;for _ in pairs(db.presets)do bankCount=bankCount+1 end
 for i=1,3 do
  if i>1 then h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);p=h.C.plannerFrame;h:click(p.buildButton);assert(p.proposal)end
  local expected=copy(p.proposal.plan);local check=forbiddenSaveWork(h)
  p.replaceCheck:SetChecked(1);h:fire(p.replaceCheck,'OnClick');h:click(p.applyButton);h:click(h:button(p.confirmFrame,'Replace'));check()
  local n=0;for _ in pairs(db.presets)do n=n+1 end;assert(n==bankCount and db.currentPreset=='Original' and h.C.PlannerEqual(expected,h:preset()),'repeat overwrite changed identity/data or duplicated the profile')
 end
end)

test('invalidate and close discard the validation snapshot with the staged proposal',function()
 local h,p=start();assert(p.saveCheck);p.countInputs['mage:rdps']:SetText('3');assert(not p.proposal and not p.saveCheck,'input change retained a stale validation snapshot')
 h:click(p.buildButton);assert(p.proposal and p.saveCheck);h:click(h:button(p,'Cancel'));assert(not p.proposal and not p.saveCheck and not p.session)
end)

print("Shir's Raid Builder save plan tests: "..(fail==0 and 'PASS'or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'save plan regressions failed')
