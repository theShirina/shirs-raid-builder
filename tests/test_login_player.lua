-- Exact Lua 5.0.3; registered login events and saved tables, no game input.
local f=assert(io.open('test_individual_editor.lua'));local source=f:read('*a');f:close()
local cut=assert(string.find(source,'\nlocal failures, passes=',1,true))
local prefix=string.sub(source,1,cut-1)
local opening="    env.SlashCmdList.SHIRSRAIDBUILDER('demo') -- Opens real main constructor without server requests."
local a,b=string.find(prefix,opening,1,true);assert(a);prefix=string.sub(prefix,1,a-1)..'    -- Login fixture deliberately does not open the UI.'..string.sub(prefix,b+1)
local runtime=os.getenv('SRB_LOGIN_ADDON_DIR')
if runtime then
 local old="'../addon/ShirsRaidBuilder/'..name";local x,y=string.find(prefix,old,1,true);assert(x)
 prefix=string.sub(prefix,1,x-1)..string.format('%q',runtime..'/')..'..name'..string.sub(prefix,y+1)
end
local boot=assert(loadstring(prefix..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn)
 local ok,why=pcall(fn)
 if ok then pass=pass+1;print('PASS '..name)else fail=fail+1;print('FAIL '..name..': '..tostring(why))end
end
local function dump(v)
 if type(v)~='table'then return type(v)=='string'and string.format('%q',v)or tostring(v)end
 local out={};for k,x in pairs(v)do table.insert(out,'['..dump(k)..']='..dump(x))end
 table.sort(out);return '{'..table.concat(out,',')..'}'
end
local function copy(v)return assert(loadstring('return '..dump(v)))()end
local function event(h,name,value)
 local list={};for _,w in ipairs(h.frames)do if w.events[name]and w:GetScript('OnEvent')then table.insert(list,w)end end
 assert(table.getn(list)>0,'missing registered event '..name)
 h.env.event=name;h.env.arg1=value
 for _,w in ipairs(list)do h.env.this=w;w:GetScript('OnEvent')()end
 h.env.event=nil;h.env.arg1=nil;h.env.this=nil
end
local function humans(h,p)
 local names={};for i=1,40 do local e=p.entries[i];if h.C.IsPlayerEntry(e)then table.insert(names,e.charName..'@'..i)end end
 return table.concat(names,',')
end
local function count(h,p,name)
 local n=0;for i=1,40 do local e=p.entries[i];if h.C.IsPlayerEntry(e)and string.lower(e.charName or '')==string.lower(name)then n=n+1 end end;return n
end
local function companion(i)
 if i==1 then return {kind='legacy',charName='Before',sourceName='Before',whisperName='Before-lite',class='warrior',role='tank',denyList={'Cleave'},setupRules={}}end
 return {kind='normal',account=i==8 and 'After' or 'Before',tier='t5r',class='mage',role='rdps',spec='frost',race='gnome',gender='female',tag=i}
end
local function shape()
 local p={entries={},denyRules={},setupRules={}}
 for i=1,40 do if i<=34 or i==36 or i==37 then p.entries[i]=companion(i)else p.entries[i]={kind='empty'}end end
 return p
end
local function login(db,name,class)
 local h=boot(db,name);h.sent={}
 h.env.UnitClass=function()return class or 'Warrior',string.upper(class or 'Warrior')end
 h.env.GetAddOnMetadata=function()return 'fixture'end
 h.env.SendChatMessage=function(message,channel)table.insert(h.sent,{message=message,channel=channel})end
 h.env.SendAddonMessage=function(prefix,message,channel,target)table.insert(h.sent,{prefix=prefix,message=message,channel=channel,target=target})end
 h.trace={};local ensure=h.C.EnsurePlayerSlot
 h.C.EnsurePlayerSlot=function(entries,...)
  local p={entries=entries};local before=humans(h,p);local slot,why=ensure(entries,unpack(arg))
  table.insert(h.trace,(h.env.event or 'UI')..': '..before..' -> '..humans(h,p));return slot,why
 end
 event(h,'ADDON_LOADED','UnrelatedAddon');assert(not h.env.ShirsRaidBuilderMainFrame)
 event(h,'ADDON_LOADED','ShirsRaidBuilder');assert(not h.env.ShirsRaidBuilderMainFrame)
 event(h,'VARIABLES_LOADED');assert(not h.env.ShirsRaidBuilderMainFrame,'login opened planner')
 event(h,'PLAYER_ENTERING_WORLD');assert(not h.env.ShirsRaidBuilderMainFrame,'world entry opened planner')
 assert(h.env.GetNumRaidMembers()==0 and h.env.GetNumPartyMembers()==0,'fixture is not ungrouped')
 for _,m in ipairs(h.sent)do local text=m.message or '';assert(text=='.z addinvite list'or text=='.z addlegacy list'or (not string.find(text,' addinvite ',1,true)and not string.find(text,' addlegacy ',1,true)),'login attempted a hire: '..text)end
 return h
end
local function open(h)h.env.SlashCmdList.SHIRSRAIDBUILDER('');return h.env.ShirsRaidBuilderMainFrame end
local function assertCompanions(h,p,before)
 for i=1,40 do local e=before[i];if e and(e.kind=='normal'or e.kind=='legacy'or e.kind=='guest')then assert(h.C.PlannerEqual(e,p.entries[i]),'companion moved/changed at '..i)end end
end
local read=os.getenv('SRB_LOGIN_READ')
local control=os.getenv('SRB_LOGIN_CONTROL')
if control then
 local db=read and assert(loadfile(read))()or {currentPreset='Plan',presets={Plan=shape()}}
 local h=login(db,control=='A'and'Before'or'After',control=='A'and'Warrior'or'Paladin')
 for _,line in ipairs(h.trace)do print('TRACE '..line)end
 print('CONTROL '..control..' filled='..h.C.FilledCount(h:preset().entries)..' humans='..humans(h,h:preset()))
 local out=os.getenv('SRB_LOGIN_WRITE');if out then local file=assert(io.open(out,'w'));file:write('return '..dump(db));file:close()end
 if control=='B'then assert(count(h,h:preset(),'Before')==0,'previous self retained across ordinary login')end
 print('historical login control: PASS');return
end
local step=os.getenv('SRB_LOGIN_STEP')
if step then
 local db=read and assert(loadfile(read))()or {currentPreset='Plan',presets={Plan=shape(),Other=shape(),Sparse={entries={[40]={kind='empty'}},denyRules={},setupRules={}}}}
 local before=copy(db.presets.Plan.entries)
 local name=step=='A'and'Before'or step=='B'and'After'or'Third'
 local h=login(db,name,step=='B'and'Paladin'or'Warrior')
 -- Start with self at35, matching the reported 36-companion layout.
 if step=='A'then
  assert(db.presets.Plan.entries[35].charName=='Before','initial automatic self was not placed at35')
  local main=open(h);h:choose(h:button(main,'Plan'),'Other');h:choose(h:button(main,'Other'),'Sparse');h:choose(h:button(main,'Sparse'),'Plan')
 end
 for _,line in ipairs(h.trace)do print('TRACE '..line)end
 for key,p in pairs(db.presets)do
  if step~='A'then assert(count(h,p,'Before')==0,'previous automatic Before survived login in '..key..': '..humans(h,p))end
  if step=='C'then assert(count(h,p,'After')==0,'previous automatic After survived login in '..key)end
 end
 assertCompanions(h,db.presets.Plan,before)
 local main=h.env.ShirsRaidBuilderMainFrame or open(h)
 for n=1,3 do event(h,'PLAYER_ENTERING_WORLD');h.env.RefreshComposition();h.env.SlashCmdList.SHIRSRAIDBUILDER('');h.env.SlashCmdList.SHIRSRAIDBUILDER('')end
 for _,key in ipairs({'Other','Sparse','Plan'})do h:choose(h:button(main,db.currentPreset),key);assert(count(h,h:preset(),name)==1,'current self not exactly once in '..key)end
 if step~='A'then for _,p in pairs(db.presets)do assert(count(h,p,'Before')==0,'reopen restored previous self')end end
 local out=os.getenv('SRB_LOGIN_WRITE');if out then local file=assert(io.open(out,'w'));file:write('return '..dump(db));file:close()end
 print("Shir's Raid Builder fresh login "..step..': PASS; '..humans(h,db.presets.Plan));return
end

test('new automatic self at35 retires on ordinary ungrouped login without UI',function()
 local db={currentPreset='Plan',presets={Plan=shape()}};local a=login(db,'Before','Warrior');local before=copy(a:preset().entries)
 assert(a:preset().entries[35].charName=='Before'and a.C.FilledCount(a:preset().entries)==37)
 local b=login(copy(db),'After','Paladin');local p=b:preset()
 for _,line in ipairs(b.trace)do print('TRACE '..line)end
 assert(count(b,p,'Before')==0,'previous automatic self remains: '..humans(b,p))
 assert(count(b,p,'After')==1 and b.C.FilledCount(p.entries)==37,'new login increased occupancy')
 assertCompanions(b,p,before)
 open(b);assert(b.env.ShirsRaidBuilderMainFrame.countText:GetText()=='37/40')
 assert(string.find(b.env.ShirsRaidBuilderMainFrame.roleText:GetText(),'Humans 1',1,true))
end)

test('unmarked existing humans survive; same account is not proof of automatic origin',function()
 local p=shape();p.entries[35]={kind='player',charName='Before',class='warrior',role='mdps'}
 local db={currentPreset='Plan',presets={Plan=p},knownCharacters={Before=true,After=true},characterLevels={Before=60,After=60}}
 local h=login(db,'After','Paladin');assert(count(h,p,'Before')==1 and count(h,p,'After')==1,'ambiguous legacy human deleted')
 assert(not p.entries[35].autoPlayerName,'unmarked human retroactively claimed as automatic')
 assert(p.entries[38].charName=='After','legacy shape does not match first-empty38 evidence')
 local again=login(copy(db),'Third');assert(count(again,again:preset(),'Before')==1 and count(again,again:preset(),'After')==0,'proven automatic and ambiguous legacy origins conflated')
end)

test('manual current human stays manual after visiting that character and switching away',function()
 local p={entries={{kind='player',charName='Before',class='warrior',role='mdps',manualNote='Keep me'}},denyRules={},setupRules={}}
 local a=login({currentPreset='Plan',presets={Plan=p}},'Before');assert(not p.entries[1].autoPlayerName,'manual current row marked disposable')
 local b=login(copy(a.env.ShirsRaidBuilderDB),'After');assert(count(b,b:preset(),'Before')==1 and b:preset().entries[1].manualNote=='Keep me','manual current row lost on next login')
end)

test('multiple old unmarked humans never disappear during migration',function()
 local p=shape();p.entries[35]={kind='player',charName='Before',class='warrior',role='mdps'};p.entries[38]={kind='player',charName='After',class='paladin',role='mdps'};p.entries[39]={kind='player',charName='Visitor',class='mage',role='rdps'}
 local h=login({currentPreset='Plan',presets={Plan=p}},'Third');assert(count(h,p,'Before')==1 and count(h,p,'After')==1 and count(h,p,'Visitor')==1 and count(h,p,'Third')==1,'legacy migration silently lost a human')
end)

test('a full companion-only plan fails visibly without changing any occupied slot',function()
 for _,preferred in ipairs({false,40})do
  local p={entries={},denyRules={},setupRules={},plannerPlayerSlot=preferred};for i=1,40 do p.entries[i]=companion(i)end
  local before=copy(p.entries);local h=login({currentPreset='Plan',presets={Plan=p}},'Current')
  assertCompanions(h,p,before);assert(count(h,p,'Current')==0,'full plan overwrote companion')
  assert(string.find(table.concat(h.messages,'\n'),'40',1,true),'full plan has no clear capacity warning')
 end
end)

test('preferred automatic placement does not move a companion occupying slot40',function()
 local p=shape();p.plannerPlayerSlot=40;p.entries[40]=companion(40)
 local before=copy(p.entries);local h=login({currentPreset='Plan',presets={Plan=p}},'Current');assertCompanions(h,p,before);assert(count(h,p,'Current')==1,'free safe slot was not used')
end)

test('invalid current identity leaves tracked previous self intact',function()
 local a=login({currentPreset='Plan',presets={Plan=shape()}},'Before');local db=copy(a.env.ShirsRaidBuilderDB)
 local h=boot(db,'After');h.env.UnitName=function()return nil end
 event(h,'VARIABLES_LOADED');assert(count(h,h:preset(),'Before')==1,'unknown identity retired previous self')
end)

test('manual row wins over a duplicate automatic self in ordinary and generated plans',function()
 for _,preferred in ipairs({false,40})do
  local p={entries={[5]={kind='player',charName='Current',class='warrior',role='mdps',autoPlayerName='current'},[39]={kind='player',charName='Current',class='warrior',role='mdps',manualNote='Keep deliberate row'}},denyRules={},setupRules={},plannerPlayerSlot=preferred}
  local h=login({currentPreset='Plan',presets={Plan=p}},'Current')
  assert(count(h,p,'Current')==1,'duplicate current self survived')
  local kept;for _,e in ipairs(p.entries)do if e.kind=='player'then kept=e end end
  assert(kept and not kept.autoPlayerName and kept.manualNote=='Keep deliberate row','automatic duplicate replaced the deliberate row')
  local b=login(copy(h.env.ShirsRaidBuilderDB),'After');assert(count(b,b:preset(),'Current')==1,'visited manual human was removed later')
 end
end)

test('malformed or mismatched provenance cannot delete a saved human',function()
 for _,marker in ipairs({true,false,{},'wrong','Before'})do
  local p={entries={{kind='player',charName='Before',class='warrior',role='mdps',autoPlayerName=marker}},denyRules={},setupRules={}}
  local h=login({currentPreset='Plan',presets={Plan=p}},'After');assert(count(h,p,'Before')==1,'bad origin authorized human deletion')
 end
end)

test('renamed identity does not inherit authority to delete another human',function()
 local a=login({currentPreset='Plan',presets={Plan=shape()}},'Before');local db=copy(a.env.ShirsRaidBuilderDB)
 db.presets.Plan.entries[35].charName='Renamed'
 local b=login(db,'After');assert(count(b,b:preset(),'Renamed')==1 and count(b,b:preset(),'After')==1,'old origin deleted renamed human')
end)

test('same identity with different case stays exactly once and keeps its automatic history',function()
 local a=login({currentPreset='Plan',presets={Plan=shape()}},'Before');local b=login(copy(a.env.ShirsRaidBuilderDB),'bEfOrE')
 assert(count(b,b:preset(),'Before')==1 and b:preset().entries[35].autoPlayerName=='before','case-only relog duplicated or dropped automatic origin')
 local c=login(copy(b.env.ShirsRaidBuilderDB),'After');assert(count(c,c:preset(),'Before')==0,'case-normalized automatic self did not retire')
end)

test('39 companions and the previous automatic self retain all companion slots',function()
 for _,preferred in ipairs({false,40})do
  local p={entries={},denyRules={},setupRules={},plannerPlayerSlot=preferred}
  for i=1,40 do p.entries[i]=companion(i)end
  p.entries[35]={kind='player',charName='Before',class='warrior',role='mdps',autoPlayerName='before'}
  local before=copy(p.entries);local h=login({currentPreset='Plan',presets={Plan=p}},'After')
  assert(count(h,p,'Before')==0 and count(h,p,'After')==1 and h.C.FilledCount(p.entries)==40,'full safe replacement failed')
  assertCompanions(h,p,before);assert(p.entries[35].charName=='After','normalization moved a companion to force self40')
 end
end)

test('inactive profiles only retire proven automatic rows and are not populated on login',function()
 local untouched={entries={[17]=companion(17)},denyRules={},setupRules={},custom='Retain'}
 local db={currentPreset='Plan',presets={Plan=shape(),Untouched=copy(untouched),Old={entries={[40]={kind='player',charName='Before',class='warrior',role='mdps',autoPlayerName='before'},[2]=companion(2)},denyRules={},setupRules={}}}}
 local h=login(db,'After');assert(h.C.PlannerEqual(db.presets.Untouched,untouched),'login mutated an inactive plan with no automatic row')
 assert(db.presets.Old.entries[40].kind=='empty'and count(h,db.presets.Old,'After')==0,'inactive plan retained stale automatic self or imported current self')
 assert(h.C.PlannerEqual(db.presets.Old.entries[2],companion(2)),'inactive cleanup changed a companion')
end)

test('Hire and Sort banks retire only their automatic self while manual captures remain',function()
 local db={uiMode='sort',currentPreset='Hire',presets={Hire={entries={[40]={kind='player',charName='Before',class='warrior',role='mdps',autoPlayerName='before'}},denyRules={},setupRules={}}},currentSortPreset='Captured',sortPresets={Captured={entries={[3]={kind='player',charName='Visitor',class='mage',role='rdps'},[40]={kind='player',charName='Before',class='warrior',role='mdps',autoPlayerName='before'}},denyRules={},setupRules={},sortLayout=true}}}
 local h=login(db,'After');assert(count(h,db.presets.Hire,'Before')==0 and count(h,db.presets.Hire,'After')==0,'inactive Hire plan populated from Sort login')
 assert(count(h,db.sortPresets.Captured,'Before')==0 and count(h,db.sortPresets.Captured,'Visitor')==1 and count(h,db.sortPresets.Captured,'After')==1,'Sort capture manual/automatic rows conflated')
 assert(db.sortPresets.Captured.sortLayout and db.uiMode=='sort','login changed workflow or capture state')
end)

test('newly built plans retain automatic origin through save and a different login',function()
 local a=login({currentPreset='Plan',presets={Plan=shape()}},'Before');local r=assert(a.C.PlannerBuild({entries={}},{},{counts={},sources={},player={name='Before',class='warrior',role='mdps'}}))
 assert(r.plan.entries[40].autoPlayerName=='before','new proposal failed to mark automatic self')
 a.env.ShirsRaidBuilderDB.presets.Built=r.plan
 local b=login(copy(a.env.ShirsRaidBuilderDB),'After');assert(count(b,b.env.ShirsRaidBuilderDB.presets.Built,'Before')==0,'saved generated plan retained automatic former self')
end)

test('manual local import preserves proven automatic history without aliasing deletion',function()
 local a=login({currentPreset='Plan',presets={Plan=shape(),Copy={entries={},denyRules={},setupRules={}}}},'Before');local db=a.env.ShirsRaidBuilderDB
 db.currentPreset='Copy';assert(a.C.ImportPreset(db,'hire','Plan','Copy'))
 local original=copy(db.presets.Plan);local b=login(copy(db),'After')
 assert(count(b,b.env.ShirsRaidBuilderDB.presets.Plan,'Before')==0 and count(b,b.env.ShirsRaidBuilderDB.presets.Copy,'Before')==0,'import lost known automatic origin')
 assert(count(a,db.presets.Plan,'Before')==1 and a.C.PlannerEqual(original,db.presets.Plan),'fresh login mutated a separate source environment')
end)

test('wire sharing does not turn a remote human into a locally automatic self',function()
 local a=login({currentPreset='Plan',presets={Plan=shape()}},'Before');local wire=assert(a.C.PlanEncode(a:preset(),'hire','Shared'));local decoded=assert(a.C.PlanDecode(wire))
 assert(decoded.entries[35].kind=='player'and not decoded.entries[35].autoPlayerName,'wire imported local deletion authority')
end)

test('low-level current self is included without importing remembered other characters',function()
 local db={currentPreset='Plan',presets={Plan={entries={},denyRules={},setupRules={}}},knownCharacters={Visitor=true},characterLevels={Visitor=60},inviteCharacters={Visitor={name='Visitor',level=60,raidLicense='t5r'}}}
 local h=boot(db,'Current');h.env.UnitLevel=function()return 20 end
 event(h,'ADDON_LOADED','ShirsRaidBuilder');event(h,'VARIABLES_LOADED');event(h,'PLAYER_ENTERING_WORLD')
 assert(count(h,h:preset(),'Current')==1 and count(h,h:preset(),'Visitor')==0,'current self was level-filtered or remembered alt imported')
end)

test('missing SavedVariable binds a real table before writing automatic self',function()
 local h=boot({},'Current');h.env.ShirsRaidBuilderDB=nil;event(h,'ADDON_LOADED','ShirsRaidBuilder');event(h,'VARIABLES_LOADED')
 local db=h.env.ShirsRaidBuilderDB;assert(type(db)=='table'and count(h,db.presets[db.currentPreset],'Current')==1,'fresh account self not bound for saving')
 assert(not h.env.ShirsRaidBuilderMainFrame,'fresh account unexpectedly opened planner')
end)

test('full-plan warning stays bounded across repeated registered world-entry events',function()
 local p={entries={},denyRules={},setupRules={}};for i=1,40 do p.entries[i]=companion(i)end
 local h=login({currentPreset='Plan',presets={Plan=p}},'Current');local n=table.getn(h.messages)
 for i=1,20 do event(h,'PLAYER_ENTERING_WORLD')end
 assert(table.getn(h.messages)==n,'capacity warning repeated on every event')
end)

test('a full plan with current self keeps that self and every companion in place',function()
 for _,automatic in ipairs({false,true})do
  local p={entries={},denyRules={},setupRules={},plannerPlayerSlot=40}
  for i=1,40 do p.entries[i]=companion(i)end
  p.entries[35]={kind='player',charName='Current',class='warrior',role='mdps',manualNote='Keep metadata'}
  if automatic then p.entries[35].autoPlayerName='current'end
  local before=copy(p.entries);local h=login({currentPreset='Plan',presets={Plan=p}},'Current')
  assert(count(h,p,'Current')==1 and p.entries[35].charName=='Current','full plan lost existing self')
  assertCompanions(h,p,before);assert(h.C.PlannerEqual(before,p.entries),'full plan changed current self metadata or slot')
 end
end)

print("Shir's Raid Builder login player tests: "..(fail==0 and'PASS'or'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'login player regressions failed')
