-- Detected party/raid players on the Hire board. Exact Lua 5.0.3, registered
-- roster/addon events, OnUpdate driver and drag handlers; synthetic roster and
-- GRINFO only. Does not prove live Microbot replies or native pixels.
local f=assert(io.open('test_board_plan_lifecycle.lua'));local src=f:read('*a');f:close()
local stop=assert(string.find(src,'\nlocal pass,fail,states=',1,true))
local boot=assert(loadstring(string.sub(src,1,stop-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn)
 local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..name)else fail=fail+1;print('FAIL '..name..': '..tostring(e))end
end
local function dump(v)
 if type(v)~='table'then return type(v)=='string'and string.format('%q',v)or tostring(v)end
 local out={};for k,x in pairs(v)do table.insert(out,'['..dump(k)..']='..dump(x))end;table.sort(out);return '{'..table.concat(out,',')..'}'
end

local function companions()
 return {
  [1]={kind='normal',account='Tester',tier='t3r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'},
  [2]={kind='legacy',charName='Shirsham',sourceName='Shirsham',class='shaman',role='healer',denyList={'Lightning Bolt'}},
  [3]={kind='normal',account='Tester',tier='t2r',class='warrior',role='tank',spec='default',race='human',gender='male'},
 }
end
-- Every non-player row with its slot: companions must never change except by an intentional move.
local function companionDump(p)
 local out={};for i=1,40 do local e=p.entries[i];if e and e.kind~='player'and e.kind~='empty'then out[i]=e end end;return dump(out)
end
local function fixture(opts)
 opts=opts or {}
 local a={entries={},denyRules={},setupRules={},plannerPlayerSlot=opts.generated and 40 or nil}
 for i=1,40 do a.entries[i]={kind='empty'}end
 for i,e in pairs(companions())do a.entries[i]=e end
 a.entries[40]={kind='player',charName='Tester',class='shaman',role='healer'}
 local b={entries={{kind='normal',account='Tester',tier='t1r',class='rogue',role='mdps',spec='default',race='human',gender='male'}},denyRules={},setupRules={}}
 local db={currentPreset='A',presets={A=a,B=b},characterRoles={}}
 if opts.mutate then opts.mutate(db)end
 local h=boot(db,'Tester','Shaman')
 h.clock=100;h.env.GetTime=function()return h.clock end
 h.asks,h.actions={}, {}
 h.env.SendAddonMessage=function(prefix,text,channel)
  assert(prefix=='nexus'and text=='GRINFO:ALL:FULL'and channel=='BATTLEGROUND','unexpected addon message '..tostring(prefix)..' '..tostring(text))
  table.insert(h.asks,h.clock)
 end
 for _,key in ipairs({'SendChatMessage','InviteByName','UninviteByName','UninviteUnit','ConvertToRaid','SetRaidSubgroup','SwapRaidSubgroup'})do
  local name=key;h.env[name]=function()table.insert(h.actions,name);error('unexpected game action: '..name)end
 end
 return h
end
local function party(h,members)
 h.members=members
 h.env.GetNumRaidMembers=function()return 0 end
 h.env.GetNumPartyMembers=function()return table.getn(h.members)end
 local function member(unit)local _,_,i=string.find(unit or'','^party(%d+)$');return i and h.members[tonumber(i)]end
 h.env.UnitName=function(unit)if unit=='player'then return 'Tester'end;local m=member(unit);return m and m[1]end
 h.env.UnitClass=function(unit)if unit=='player'then return 'Shaman','SHAMAN'end;local m=member(unit);if m and m[2] then return m[2],string.upper(m[2])end end
end
local function raid(h,members)
 local rows={{'Tester','Shaman'}};for _,m in ipairs(members)do table.insert(rows,m)end;h.members=rows
 h.env.GetNumPartyMembers=function()return 0 end
 h.env.GetNumRaidMembers=function()return table.getn(h.members)end
 h.env.GetRaidRosterInfo=function(i)local r=h.members[i];if r then return r[1],0,math.floor((i-1)/5)+1,60,r[2],r[2] and string.upper(r[2]),'Zone',1 end end
end
local function event(h,name,a1,a2,a3,a4)
 local n=0
 for _,w in ipairs(h.frames)do if w.events[name]and w:GetScript('OnEvent')then
  n=n+1;h.env.event=name;h.env.this=w;h.env.arg1=a1;h.env.arg2=a2;h.env.arg3=a3;h.env.arg4=a4;w:GetScript('OnEvent')()
 end end
 h.env.event=nil;h.env.this=nil;h.env.arg1=nil;h.env.arg2=nil;h.env.arg3=nil;h.env.arg4=nil
 assert(n>0,'no registered handler for '..name)
end
local function tick(h,t)
 h.clock=t;local w=h.C.groupFrame;assert(w and w:GetScript('OnUpdate'),'group driver missing')
 h.env.this=w;h.env.arg1=0.5;w:GetScript('OnUpdate')();h.env.this=nil;h.env.arg1=nil
end
local function grinfo(h,records)
 event(h,'CHAT_MSG_ADDON','[nexus] GRINFO:ALL:FULL '..table.concat(records,' '),'','UNKNOWN','Tester')
end
local function slotOf(h,name,p)
 local at,n=nil,0
 for i,e in ipairs((p or h:preset()).entries)do if e.kind=='player'and string.lower(e.charName or'')==string.lower(name)then at=i;n=n+1 end end
 assert(n<=1,'duplicate rows for '..name..': '..n);return at
end
local function said(h,text)local n=0;for _,m in ipairs(h.messages)do if string.find(m,text,1,true)then n=n+1 end end;return n end
local function row(h,index)
 local w=h.C.boardPools.entry[index];assert(w and w:IsVisible()and w.boardIndex==index,'visible card missing at '..index);return w
end
local function drag(h,from,to)
 local source=row(h,from);local kind=h.C.IsFilledEntry(h:preset().entries[to])and'entry'or'empty'
 local target=h.C.boardPools[kind][to];assert(target and target:IsVisible(),'drop target missing')
 h.env.GetCursorPosition=function()return (target:GetLeft()+target:GetRight())/2,(target:GetBottom()+target:GetTop())/2 end
 h:fire(source,'OnDragStart','LeftButton')
 for _,w in ipairs(h.frames)do if w.scripts.OnUpdate and w.kind=='Frame'and w.name==nil and w.parent==nil and next(w.events)==nil then h:fire(w,'OnUpdate',0.016)end end
 h:fire(source,'OnDragStop','LeftButton')
end
-- Bob is a human in the party; Compmage is a hired companion owned by Tester.
local function joined(h,opts)
 opts=opts or {}
 local members={{'Bob','Priest'},{'Compmage','Mage'}};if opts.extra then table.insert(members,opts.extra)end
 if opts.raid then raid(h,members)else party(h,members)end
 h.clock=100;event(h,opts.raid and'RAID_ROSTER_UPDATE'or'PARTY_MEMBERS_CHANGED');tick(h,100)
 tick(h,103.2) -- Every member has been in the group for the margin: one request.
 h.clock=103.4;grinfo(h,opts.records or {'Compmage:gnome:mage:rdps:t3r:Tester'})
 tick(h,104)
end

test('classification needs evidence and leaves unclear members alone',function()
 local C=fixture().C
 local roster={{name='Tester',class='SHAMAN'},{name='Owner',class='WARRIOR'},{name='Listed',class='MAGE'},{name='Shirsha-lite',class='SHAMAN'},{name='Late',class='PRIEST'},{name='Odd1',class='ROGUE'},{name='Noclass'}}
 local seen={owner=100,listed=100,['shirsha-lite']=100,late=100,odd1=100,noclass=100}
 local list={{name='Listed',owner='Owner'}}
 local function names(t)local out={};for _,x in ipairs(t)do table.insert(out,x.name..(x.reason and(':'..x.reason)or''))end;return table.concat(out,',')end
 local p,c,a=C.ClassifyGroupMembers(roster,'Tester',{list=list,at=104},seen)
 assert(names(p)=='Late,Owner','fresh absence and owner evidence: '..names(p))
 assert(c.listed and c['shirsha-lite']and not c.owner and not c.tester,'companion set')
 assert(names(a)=='Noclass:class,Odd1:unclear','ambiguous: '..names(a))
 p,c,a=C.ClassifyGroupMembers(roster,'Tester',{list=list,at=102},seen)
 assert(names(p)=='Owner'and string.find(names(a),'Late:wait',1,true),'a list from before the margin cannot confirm absence')
 p,c,a=C.ClassifyGroupMembers(roster,'Tester',{list=nil},seen)
 assert(names(p)==''and string.find(names(a),'Owner:wait',1,true),'no list confirms nobody')
 p,c,a=C.ClassifyGroupMembers(roster,'Tester',{list={{name='Listed',owner='Owner'},{name='Unknown',owner='Owner'}},at=110},seen)
 assert(names(p)=='Owner'and string.find(names(a),'Late:unclear',1,true),'an Unknown record makes absence unclear')
end)

test('join adds a confirmed player to the highest empty slot with one bounded request',function()
 local h=fixture();local p=h:preset();local before=companionDump(p)
 party(h,{{'Bob','Priest'},{'Compmage','Mage'}})
 event(h,'PARTY_MEMBERS_CHANGED');tick(h,100);tick(h,101);tick(h,102)
 assert(not slotOf(h,'Bob')and table.getn(h.asks)==0,'added or asked before the margin')
 tick(h,103.2);assert(table.getn(h.asks)==1,'expected one GRINFO request, got '..table.getn(h.asks))
 tick(h,104);tick(h,105);assert(table.getn(h.asks)==1,'repeated request before a reply')
 h.clock=105.2;grinfo(h,{'Compmage:gnome:mage:rdps:t3r:Tester'});tick(h,106)
 assert(slotOf(h,'Bob')==39,'Bob not at the tail: '..tostring(slotOf(h,'Bob')))
 local bob=p.entries[39];assert(bob.autoGroupName=='bob'and bob.class=='priest'and bob.role=='rdps','detected row shape '..dump(bob))
 assert(not slotOf(h,'Compmage'),'companion added as a human')
 assert(companionDump(p)==before and slotOf(h,'Tester')==40,'companions or self changed')
 for i=1,10 do tick(h,106+i);h.env.RefreshComposition()end
 assert(table.getn(h.asks)==1 and slotOf(h,'Bob')==39,'refresh repeated a request or moved Bob')
 assert(table.getn(h.actions)==0,'live action escaped')
end)

test('a reply that predates the margin never confirms; owners are confirmed at once',function()
 local h=fixture();party(h,{{'Bob','Priest'},{'Carl','Warrior'}})
 event(h,'PARTY_MEMBERS_CHANGED');tick(h,100)
 h.clock=100.6;grinfo(h,{'Compmage:gnome:mage:rdps:t3r:Carl'});tick(h,101)
 assert(slotOf(h,'Carl')==39 and not slotOf(h,'Bob'),'owner evidence or early absence handled wrongly')
end)

test('raid roster joins and leaves keep one row per player and never touch companions',function()
 local h=fixture();local p=h:preset();local before=companionDump(p)
 joined(h,{raid=true});assert(slotOf(h,'Bob')==39,'raid join')
 raid(h,{{'Bob','Priest'},{'Compmage','Mage'},{'Dana','Druid'}});h.clock=110;event(h,'RAID_ROSTER_UPDATE');tick(h,110)
 tick(h,113.2);h.clock=113.4;grinfo(h,{'Compmage:gnome:mage:rdps:t3r:Tester'});tick(h,114)
 assert(slotOf(h,'Bob')==39 and slotOf(h,'Dana')==38,'second join')
 raid(h,{{'Compmage','Mage'},{'Dana','Druid'}});event(h,'RAID_ROSTER_UPDATE');tick(h,115)
 assert(not slotOf(h,'Bob')and slotOf(h,'Dana')==38 and p.entries[39].kind=='empty','leave did not retire only Bob')
 raid(h,{});event(h,'RAID_ROSTER_UPDATE');tick(h,116)
 assert(not slotOf(h,'Dana')and companionDump(p)==before and slotOf(h,'Tester')==40,'leaving the raid left stale rows or changed companions')
 assert(h.C.FilledCount(p.entries)==4,'unexpected occupancy')
end)

test('rejoin needs fresh evidence again',function()
 local h=fixture();joined(h)
 party(h,{{'Compmage','Mage'}});event(h,'PARTY_MEMBERS_CHANGED');tick(h,110);assert(not slotOf(h,'Bob'),'leave')
 party(h,{{'Bob','Priest'},{'Compmage','Mage'}});h.clock=120;event(h,'PARTY_MEMBERS_CHANGED');tick(h,120)
 assert(not slotOf(h,'Bob'),'stale reply from the first visit confirmed the rejoin')
 local asks=table.getn(h.asks);tick(h,123.2);assert(table.getn(h.asks)==asks+1,'no fresh request after rejoin')
 h.clock=123.4;grinfo(h,{'Compmage:gnome:mage:rdps:t3r:Tester'});tick(h,124);assert(slotOf(h,'Bob')==39,'rejoin not added')
end)

test('full plan stays unchanged and says why once',function()
 local h=fixture({mutate=function(db)
  local e=db.presets.A.entries;for i=4,39 do e[i]={kind='normal',account='Tester',tier='t1r',class='rogue',role='mdps',spec='default',race='human',gender='male'}end
 end})
 local p=h:preset();local before=dump(p.entries);joined(h)
 assert(dump(p.entries)==before,'full plan changed')
 assert(said(h,'Plan full: Bob')==1,'full-plan reason missing')
 for i=1,5 do tick(h,104+i);h.env.RefreshComposition()end
 assert(said(h,'Plan full: Bob')==1 and dump(p.entries)==before,'full-plan note repeated or plan changed')
 local empty=7;p.entries[empty]={kind='empty'};h.env.RefreshComposition()
 assert(slotOf(h,'Bob')==empty,'freed slot not used')
end)

test('ambiguous identities are reported and left out',function()
 local h=fixture();local p=h:preset();local before=dump(p.entries)
 joined(h,{records={'Compmage:gnome:mage:rdps:t3r:Tester','Unknown:gnome:mage:rdps:t3r:Tester'}})
 assert(not slotOf(h,'Bob')and dump(p.entries)==before,'Unknown record still confirmed a human')
 assert(said(h,'Not added: Bob')==1,'ambiguity not reported')
 local h2=fixture();party(h2,{{'Unknown','Priest'}});event(h2,'PARTY_MEMBERS_CHANGED');tick(h2,100);tick(h2,104)
 assert(h2.C.FilledCount(h2:preset().entries)==4,'unloaded roster name added')
end)

test('no reply at all: two requests, then a visible note, plan unchanged',function()
 local h=fixture();local p=h:preset();local before=dump(p.entries)
 party(h,{{'Bob','Priest'}});event(h,'PARTY_MEMBERS_CHANGED');tick(h,100)
 for t=103.2,140,0.5 do tick(h,t)end
 assert(table.getn(h.asks)==2,'request bound broken: '..table.getn(h.asks))
 assert(said(h,'No fresh companion list')==1 and dump(p.entries)==before,'missing note or changed plan')
end)

test('requests follow a roster event or opening the board, never plain ticks',function()
 local h=fixture();party(h,{{'Bob','Priest'}})
 h.clock=100;event(h,'PLAYER_ENTERING_WORLD')
 for t=100,125,0.5 do tick(h,t)end
 assert(table.getn(h.asks)==0,'polling sent a request without a roster event')
 local main=h.env.ShirsRaidBuilderMainFrame;main:Hide();tick(h,126);main:Show();tick(h,127)
 assert(table.getn(h.asks)==1,'opening the board did not ask once: '..table.getn(h.asks))
 for t=127.5,135,0.5 do tick(h,t)end;assert(table.getn(h.asks)==1,'reopen request repeated early')
end)

test('existing manual rows and guest names prevent duplicates; stray detected duplicates retire',function()
 local h=fixture({mutate=function(db)
  local e=db.presets.A.entries
  e[9]={kind='player',charName='Bob',class='priest',role='healer'}
  e[30]={kind='player',charName='Bob',class='priest',role='rdps',autoGroupName='bob'}
  e[31]={kind='guest',charName='Erin',companionName='Erin',account='Other',class='mage',role='rdps'}
 end})
 local p=h:preset();joined(h,{extra={'Erin','Mage'}})
 local n=0;for _,e in ipairs(p.entries)do if e.kind=='player'and e.charName=='Bob'then n=n+1 end end
 assert(n==1 and p.entries[9].charName=='Bob'and not p.entries[9].autoGroupName and p.entries[30].kind=='empty','manual Bob not kept alone')
 assert(p.entries[31].kind=='guest'and not slotOf(h,'Erin'),'guest row reclassified or duplicated')
end)

test('manual drag and swap keep both entries and refresh does not undo them',function()
 for _,generated in ipairs({false,true})do
  local h=fixture({generated=generated});local p=h:preset();joined(h)
  assert(slotOf(h,'Bob')==39,'setup')
  drag(h,39,12);assert(slotOf(h,'Bob')==12 and p.entries[39].kind=='empty','move to empty')
  for i=1,4 do tick(h,110+i);h.env.RefreshComposition()end
  assert(slotOf(h,'Bob')==12,'refresh undid the move (generated='..tostring(generated)..')')
  local mage=p.entries[1];drag(h,12,1)
  assert(slotOf(h,'Bob')==1 and p.entries[12]==mage,'swap with companion lost an entry')
  for i=1,4 do tick(h,120+i);h.env.RefreshComposition()end
  assert(slotOf(h,'Bob')==1 and p.entries[12]==mage and p.entries[12].account=='Tester'and p.entries[12].tier=='t3r','refresh undid the swap')
  assert(slotOf(h,'Tester')==40,'self moved')
  party(h,{{'Compmage','Mage'}});event(h,'PARTY_MEMBERS_CHANGED');tick(h,130)
  assert(p.entries[1].kind=='empty'and p.entries[12]==mage,'leaving after a swap moved the companion back or kept Bob')
  assert(table.getn(h.actions)==0,'live action escaped')
 end
end)

test('generated plans keep dragged manual humans in place; only a human at 40 yields to self',function()
 local h=fixture({generated=true,mutate=function(db)
  local e=db.presets.A.entries;e[20]={kind='player',charName='Mia',class='druid',role='healer'};e[39]={kind='player',charName='Ned',class='rogue',role='mdps'}
 end})
 local p=h:preset();local before=companionDump(p)
 for i=1,3 do h.env.RefreshComposition()end
 assert(slotOf(h,'Mia')==20 and slotOf(h,'Ned')==39 and slotOf(h,'Tester')==40,'refresh moved a manual human')
 drag(h,20,5);for i=1,3 do tick(h,100+i);h.env.RefreshComposition()end
 assert(slotOf(h,'Mia')==5,'refresh undid a manual human move')
 drag(h,39,14);for i=1,3 do tick(h,110+i);h.env.RefreshComposition()end
 assert(slotOf(h,'Ned')==14 and companionDump(p)==before,'second move undone or companions changed')
 -- Login as a new character: its row takes 40 and the human there moves to the old self slot only.
 local q=h.env.ShirsRaidBuilderDB.presets.A.entries;q[12]=q[40];q[40]={kind='player',charName='Ole',class='mage',role='rdps'}
 h.env.RefreshComposition()
 assert(slotOf(h,'Tester')==40 and slotOf(h,'Ole')==12 and slotOf(h,'Mia')==5 and slotOf(h,'Ned')==14,'self-at-40 moved more than the occupant')
 q[40]={kind='normal',account='Tester',tier='t1r',class='rogue',role='mdps',spec='default',race='human',gender='male'};q[25]={kind='player',charName='Tester',class='shaman',role='healer'}
 h.env.RefreshComposition();assert(slotOf(h,'Tester')==25 and q[40].kind=='normal','self displaced a companion at 40')
end)

test('X removal keeps a detected player out until they leave and rejoin',function()
 local h=fixture();local p=h:preset();joined(h)
 h:click(h:button(row(h,39),'X'));assert(not slotOf(h,'Bob'),'X did not remove')
 for i=1,4 do tick(h,110+i);h.env.RefreshComposition()end;assert(not slotOf(h,'Bob'),'removed player came back')
 party(h,{{'Compmage','Mage'}});event(h,'PARTY_MEMBERS_CHANGED');tick(h,120);assert(not p.groupPlayerSkips,'skip kept after leaving')
 party(h,{{'Bob','Priest'},{'Compmage','Mage'}});h.clock=130;event(h,'PARTY_MEMBERS_CHANGED');tick(h,130);tick(h,133.2)
 h.clock=133.4;grinfo(h,{'Compmage:gnome:mage:rdps:t3r:Tester'});tick(h,134);assert(slotOf(h,'Bob')==39,'rejoin not added')
end)

test('role totals exclude players but capacity counts their slot',function()
 local h=fixture();local p=h:preset();joined(h)
 local main=h.env.ShirsRaidBuilderMainFrame
 assert(string.find(main.roleText:GetText(),'Tank 1   Healer 1   Melee 0   Range 1',1,true),'companion totals changed: '..main.roleText:GetText())
 assert(string.find(main.roleText:GetText(),'Humans 2',1,true),'human count')
 assert(main.countText:GetText()=='5/40','capacity '..main.countText:GetText())
end)

test('Preview and Execute queues are unchanged by detected players',function()
 local h=fixture();local p=h:preset()
 local function commands(q)local out={};for _,x in ipairs(q)do table.insert(out,tostring(x.kind)..'|'..tostring(x.command)..'|'..tostring(x.target))end;table.sort(out);return table.concat(out,'\n')end
 local before,whispers=commands(h.C.BuildQueue(p)),commands(h.C.BuildWhisperQueue(p))
 joined(h);assert(slotOf(h,'Bob'),'setup')
 assert(commands(h.C.BuildQueue(p))==before and commands(h.C.BuildWhisperQueue(p))==whispers,'detected player changed hire or whisper commands')
 assert(not string.find(before,'Bob',1,true),'fixture')
end)

test('a run, sort or handoff holds the board until it ends',function()
 local h=fixture();local p=h:preset();h.C.handRunPlan={entries=p.entries}
 joined(h);assert(not slotOf(h,'Bob')and table.getn(h.asks)==0,'changed or asked during a run')
 h.C.handRunPlan=nil;tick(h,110);tick(h,111)
 assert(slotOf(h,'Bob')==39,'not applied after the run')
end)

test('inactive plans lose stale detected rows only; other plans stay byte-identical',function()
 local h=fixture({mutate=function(db)
  db.presets.C={entries={{kind='player',charName='Bob',class='priest',role='rdps',autoGroupName='bob'},{kind='player',charName='Manual',class='mage',role='rdps'}},denyRules={},setupRules={}}
 end})
 local db=h.env.ShirsRaidBuilderDB;local b=dump(db.presets.B)
 party(h,{{'Bob','Priest'}});event(h,'PARTY_MEMBERS_CHANGED');tick(h,100)
 assert(db.presets.C.entries[1].charName=='Bob','present player retired from inactive plan')
 party(h,{});event(h,'PARTY_MEMBERS_CHANGED');tick(h,101)
 assert(db.presets.C.entries[1].kind=='empty'and db.presets.C.entries[2].charName=='Manual','inactive sweep')
 assert(dump(db.presets.B)==b,'plan without detected rows changed')
end)

test('login keeps saved detected rows until the roster settles, then retires stale ones',function()
 local h=fixture({mutate=function(db)db.presets.A.entries[39]={kind='player',charName='Bob',class='priest',role='rdps',autoGroupName='bob'}end})
 party(h,{});h.clock=100;event(h,'PLAYER_ENTERING_WORLD');tick(h,100);tick(h,102)
 assert(slotOf(h,'Bob')==39,'retired before the roster was known')
 tick(h,105.5);assert(not slotOf(h,'Bob'),'stale saved row kept after roster settled')
 assert(said(h,'no automatic-player history')==0,'detected rows reported as unknown saved humans')
end)

test('logging in as a detected character hands the row to the current-self policy',function()
 local h=fixture({mutate=function(db)
  local e=db.presets.A.entries;e[40]={kind='empty'};e[38]={kind='player',charName='Tester',class='shaman',role='healer',autoGroupName='tester'}
 end})
 party(h,{});event(h,'PARTY_MEMBERS_CHANGED');tick(h,100);h.env.RefreshComposition()
 local at=slotOf(h,'Tester');assert(at,'self missing')
 local e=h:preset().entries[at];assert(not e.autoGroupName and e.autoPlayerName=='tester','self row kept detected provenance')
end)

test('saved plans keep detected rows across a fresh Lua process reload',function()
 local h=fixture();joined(h)
 local saved=assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))()
 local h2=boot(saved,'Tester','Shaman');h2.env.GetTime=function()return 200 end
 local p=h2:preset();assert(slotOf(h2,'Bob',p)==39 and p.entries[39].autoGroupName=='bob','detected row lost on reload')
 assert(companionDump(p)==companionDump(h:preset()),'companions changed across reload')
end)

print("Shir's Raid Builder group player tests: "..(fail==0 and'PASS'or'FAIL')..' ('..pass..' passed, '..fail..' failed)')
assert(fail==0,'group player regressions failed')
