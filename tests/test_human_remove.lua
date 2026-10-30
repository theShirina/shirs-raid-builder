-- Registered Vanilla board callbacks, exact Lua 5.0.3; synthetic UI/roster only.
local f=assert(io.open('test_individual_editor.lua'));local src=f:read('*a');f:close()
local at=assert(string.find(src,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(src,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn)
 local ok,e=pcall(fn)
 if ok then pass=pass+1;print('PASS '..name)else fail=fail+1;print('FAIL '..name..': '..tostring(e))end
end
local function fixture(slot,loose,selfSlot)
 local p={entries={},denyRules={},setupRules={},plannerPlayerSlot=40}
 if loose then p.plannerPlayerSlot=nil end
 for i=1,40 do p.entries[i]={kind='empty'}end
 p.entries[slot]={kind='player',charName='Visitor',class='priest',role='healer'}
 p.entries[selfSlot or 40]={kind='player',charName='Tester',class='warrior',role='tank'}
 return boot({currentPreset='Plan',presets={Plan=p,Other={entries={{kind='player',charName='Visitor',class='mage',role='rdps'}},denyRules={},setupRules={}}}})
end
local function card(h,index)
 local row=h.C.boardPools.entry[index]
 assert(row and row:IsVisible() and row.boardIndex==index,'visible card missing at '..index)
 return row
end
local function dump(v)
 if type(v)~='table'then return type(v)=='string'and string.format('%q',v)or tostring(v)end
 local parts={};for k,x in pairs(v)do table.insert(parts,'['..dump(k)..']='..dump(x))end
 table.sort(parts);return '{'..table.concat(parts,',')..'}'
end
local function absent(h,name)
 for _,e in ipairs(h:preset().entries)do
  assert(not(e.kind=='player' and string.lower(e.charName or '')==string.lower(name)),'removed human returned: '..name)
 end
end
local function safety(h)
 local calls={}
 for _,name in ipairs({'SendChatMessage','SendAddonMessage','InviteByName','UninviteByName','UninviteUnit','ConvertToRaid','SetRaidSubgroup','SwapRaidSubgroup'})do
  local key=name;h.env[key]=function(...)table.insert(calls,key);error('unexpected game action: '..key)end
 end
 return function()assert(table.getn(calls)==0,'removal emitted actions: '..table.concat(calls,','))end
end
local function event(h,name,a,b)
 local oldEvent,oldThis,oldA,oldB=h.env.event,h.env.this,h.env.arg1,h.env.arg2
 local n=0
 for _,w in ipairs(h.frames)do
  if w.events[name] and w:GetScript('OnEvent')then
   n=n+1;h.env.event=name;h.env.this=w;h.env.arg1=a;h.env.arg2=b;w:GetScript('OnEvent')()
  end
 end
 h.env.event=oldEvent;h.env.this=oldThis;h.env.arg1=oldA;h.env.arg2=oldB
 return n
end
local function liveRoster(h,player)
 local rows={{name=player or 'Tester',class='Warrior',group=8},{name='Visitor',class='Priest',group=1},{name='Companion',class='Mage',group=1}}
 h.env.GetNumRaidMembers=function()return table.getn(rows)end
 h.env.GetRaidRosterInfo=function(i)local r=rows[i];if r then return r.name,2,r.group,60,r.class,string.upper(r.class),'FixtureZone',1 end end
 h.env.UnitName=function(unit)if unit=='player'then return player or 'Tester'end;local i=tonumber(string.sub(unit,5));return rows[i] and rows[i].name end
 return rows
end

local reloadRead=os.getenv('SRB_HUMAN_RELOAD_READ')
if reloadRead then
 local saved=assert(loadfile(reloadRead))();local h=boot(saved)
 absent(h,'Visitor');assert(h.C.FilledCount(h:preset().entries)==1 and h:preset().entries[40].charName=='Tester','fresh process lost self or added a row')
 local db=h.env.ShirsRaidBuilderDB;assert(db.currentPreset=='Without Visitor' and db.presets.Plan and db.presets.Other,'fresh process lost profiles')
 assert(db.presets.Other.entries[1].charName=='Visitor','remove crossed profiles on fresh process load')
 h.env.RefreshComposition();absent(h,'Visitor')
 h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);h:click(h.C.plannerFrame.buildButton)
 for _,e in ipairs(assert(h.C.plannerFrame.proposal).plan.entries)do assert(e.charName~='Visitor','fresh Build reinserted removed human')end
 print("Shir's Raid Builder human fresh process tests: PASS");return
end

test('other human has a registered X and removing it changes only the plan',function()
 local h=fixture(39);local p=h:preset();local self=p.entries[40]
 local row=card(h,39);local x=h:button(row,'X')
 assert(x:GetScript('OnClick'),'X callback missing')
 h:click(x)
 assert(p.entries[39].kind=='empty','human remained after registered X')
 assert(p.entries[40].charName==self.charName and p.entries[40].kind=='player','self lost occupancy')
 assert(h.env.ShirsRaidBuilderMainFrame.countText:GetText()=='1/40','occupancy did not redraw')
end)

test('other human context removal is explicit and self remains protected',function()
 local h=fixture(39);local p=h:preset()
 h:fire(card(h,39),'OnMouseUp','RightButton')
 local menu=h.env.ShirsRaidBuilderContextFrame
 local remove=h:button(menu,'Remove from plan')
 h:click(remove)
 assert(p.entries[39].kind=='empty' and not menu:IsShown(),'context remove did not commit and close')
 h:fire(card(h,40),'OnMouseUp','RightButton')
 assert(not pcall(function()h:button(menu,'Remove from plan')end),'self context exposes remove')
 assert(not pcall(function()h:button(card(h,40),'X')end),'self exposes X')
 h:click(h:button(menu,'Close'))
end)

test('human hover and X explain plan-only removal rather than identifying everyone as self',function()
 local h=fixture(39);local lines={}
 h.env.GameTooltip.AddLine=function(_,text)table.insert(lines,text)end
 h:fire(card(h,39),'OnEnter')
 local text=table.concat(lines,'\n')
 assert(not string.find(text,'You.',1,true),'other human tooltip claims current self')
 assert(string.find(text,'live group',1,true),'other human tooltip omits plan-only semantics')
 local x=h:button(card(h,39),'X')
 assert(x.tipTitle=='Remove from plan' and string.find(x.tip,'live group',1,true),'X tooltip omits plan-only semantics')
end)

test('padding sparse human-tail results fills holes without overwriting occupied slots',function()
 local h=fixture(39);local visitor={kind='player',charName='Visitor',class='priest',role='healer'}
 local self={kind='player',charName='Tester',class='warrior',role='tank'}
 local entries={[39]=visitor,[40]=self};h.C.PadRaidSlots(entries,40)
 assert(entries[39]==visitor and entries[40]==self,'padding sparse tail overwrote human identities')
 assert(table.getn(entries)==40 and entries[1].kind=='empty','sparse padding did not produce forty slots')
end)

for _,position in ipairs({1,5,6,20,35,39,40})do local slot=position
 test('human X removes only its identity at slot '..slot,function()
  local h=fixture(slot,true,slot==40 and 1 or 40);local check=safety(h);local p=h:preset();local before=h.C.PlannerCopy(p)
  h:click(h:button(card(h,slot),'X'));absent(h,'Visitor')
  for i=1,40 do if i~=slot then assert(h.C.PlannerEqual(p.entries[i],before.entries[i]),'another slot changed: '..i)end end
  for i=1,20 do h.env.RefreshComposition()end;absent(h,'Visitor');check()
 end)
end

test('self guard uses identity and kind, not slot, role, leader status or name alone',function()
 local h=fixture(39);local can=h.C.CanRemoveBoardEntry
 assert(not can({kind='player',charName=' tEsTeR ',class='mage',role='rdps'}),'case/whitespace bypassed self guard')
 assert(can({kind='player',charName='Visitor',class='warrior',role='tank'}),'all human Tanks protected')
 assert(can({kind='legacy',charName='Tester',class='warrior',role='tank'}),'legacy mistaken for self')
 assert(can({kind='guest',charName='Tester',class='warrior',role='tank'}),'unresolved guest mistaken for explicit self')
 assert(not can({kind='empty'}) and not can(nil),'empty slot removable')
 h.env.UnitName=function()return nil end
 assert(not can({kind='player',charName='Visitor'}),'missing current identity did not fail closed')
 assert(can({kind='normal',account='Tester',class='mage',role='rdps'}),'missing identity blocked companion removal')
end)

test('click-time guard protects a human that has become the current character',function()
 local h=fixture(39);local p=h:preset();local before=h.C.PlannerCopy(p);local check=safety(h)
 local x=h:button(card(h,39),'X');h.env.UnitName=function()return 'Visitor'end;h:click(x)
 assert(h.C.PlannerEqual(before,p),'click-time current self was deleted');check()
end)

test('mutation guard rejects direct current-self removal as well as the UI affordances',function()
 local h=fixture(39);local callback=h:button(card(h,39),'X'):GetScript('OnClick');local remove
 for i=1,32 do local name,value=debug.getupvalue(callback,i);if not name then break end;if name=='RemoveEntry'then remove=value end end
 assert(remove,'registered X did not reach native RemoveEntry')
 local before=h.C.PlannerCopy(h:preset());remove(40)
 assert(h.C.PlannerEqual(before,h:preset()),'mutation helper removed current character')
end)

test('pooled rows rebind across human normal legacy guest and self without stale removal or growth',function()
 local h=fixture(16,true);local p=h:preset();local row=card(h,16);local stale=h:button(row,'X'):GetScript('OnClick');local check=safety(h)
 local kinds={{kind='empty'},{kind='legacy',charName='Legacy',class='mage',role='rdps'},
  {kind='normal',account='Alpha',tier='t3r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'},
  {kind='guest',charName='Unknown',companionName='Unknown',class='priest',role='healer'},
  {kind='player',charName='Visitor',class='priest',role='healer'}}
 for _,e in ipairs(kinds)do p.entries[16]=h.C.PlannerCopy(e);h.env.RefreshComposition()end
 local n=table.getn(h.frames)
 for cycle=1,100 do for _,e in ipairs(kinds)do p.entries[16]=h.C.PlannerCopy(e);h.env.RefreshComposition()end end
 assert(table.getn(h.frames)==n,'human pool introduced widget growth')
 local before=h.C.PlannerCopy(p);stale();assert(h.C.PlannerEqual(before,p),'retained callback removed rebound row')
 h:click(h:button(card(h,16),'X'));assert(p.entries[16].kind=='empty')
 p.entries[16]={kind='player',charName='Tester',class='warrior',role='tank'};h.env.RefreshComposition()
 assert(not pcall(function()h:button(card(h,16),'X')end),'pooled human X leaked onto self')
 check()
end)

test('retained X and context callbacks cannot cross a registered profile switch',function()
 local h=fixture(39);local original=h:preset();local before=h.C.PlannerCopy(original);local row=card(h,39)
 local staleX=h:button(row,'X'):GetScript('OnClick');h:fire(row,'OnMouseUp','RightButton')
 local staleContext=h:button(h.env.ShirsRaidBuilderContextFrame,'Remove from plan'):GetScript('OnClick')
 h:choose(h:button(h.env.ShirsRaidBuilderMainFrame,'Plan'),'Other');local other=h.C.PlannerCopy(h:preset())
 staleX();staleContext();assert(h.C.PlannerEqual(other,h:preset()) and h.C.PlannerEqual(before,original),'stale remove crossed profile')
 h:choose(h:button(h.env.ShirsRaidBuilderMainFrame,'Other'),'Plan')
 h:click(h:button(card(h,39),'X'));absent(h,'Visitor')
 assert(h.env.ShirsRaidBuilderDB.presets.Other.entries[1].charName=='Visitor','remove changed another profile')
end)

test('human-tail repaint preserves every remaining identity and companion metadata at full capacity',function()
 local h=fixture(39);local p=h:preset()
 for i=1,38 do p.entries[i]={kind='normal',account='Owner'..string.char(65+math.floor((i-1)/4)),tier='t3r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'}end
 h.env.RefreshComposition();local before=h.C.PlannerCopy(p.entries);local check=safety(h)
 assert(h.env.ShirsRaidBuilderMainFrame.countText:GetText()=='40/40')
 h:click(h:button(card(h,39),'X'));absent(h,'Visitor')
 assert(h.env.ShirsRaidBuilderMainFrame.countText:GetText()=='39/40','40-slot capacity not released')
 assert(h.env.ShirsRaidBuilderMainFrame.roleText:GetText()=='Tank 0   Healer 0   Melee 0   Range 38\nHumans 1','removed human changed companion totals')
 for i=1,38 do assert(h.C.PlannerEqual(before[i],p.entries[i]),'companion identity/source/tier/manual choice changed')end
 local q=h.C.BuildQueue(p);local hires=0;for _,item in ipairs(q)do if h.C.IsHireCommand(item)then hires=hires+1 end end
 assert(hires==38 and p.entries[40].charName=='Tester','current player cap/queue boundary changed');check()
end)

test('several placed human rows stay put and remain individually removable',function()
 local h=fixture(39);local p=h:preset()
 for i=1,5 do p.entries[i]={kind='player',charName='Human'..string.char(64+i),class='mage',role='rdps'}end
 h.env.RefreshComposition()
 for i=1,5 do assert(p.entries[i].charName=='Human'..string.char(64+i),'refresh moved a placed human from slot '..i)end
 assert(p.entries[39].charName=='Visitor'and p.entries[40].charName=='Tester','tail humans moved')
 local row=card(h,3);local target=row.boardEntry.charName;local stale=h:button(row,'X'):GetScript('OnClick')
 h:click(h:button(row,'X'));absent(h,target)
 local before=h.C.PlannerCopy(p);stale();assert(h.C.PlannerEqual(before,p),'old tail handler deleted newly shifted human')
 assert(h.C.FilledCount(p.entries)==6 and p.entries[40].charName=='Tester','other human identities were dropped')
 local seen={};for _,e in ipairs(p.entries)do if e.kind=='player'then assert(not seen[e.charName],'duplicated human');seen[e.charName]=true end end
 assert(not seen[target] and seen.Visitor and seen.Tester,'tail identity set changed')
end)

test('normal legacy and unresolved guest removals retain their existing behavior',function()
 for _,entry in ipairs({{kind='normal',account='Alpha',tier='t3r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'},
  {kind='legacy',charName='Tester',class='mage',role='rdps',denyList={'Frostbolt'}},
  {kind='guest',charName='Unknown',companionName='Unknown',class='priest',role='healer'}})do
  local h=fixture(39);local p=h:preset();p.entries[7]=h.C.PlannerCopy(entry);h.env.RefreshComposition();local check=safety(h)
  h:click(h:button(card(h,7),'X'));assert(p.entries[7].kind=='empty' and p.entries[40].charName=='Tester');check()
 end
end)

test('ordinary repaint roster events close reopen and reviewed Save never reinsert removed human',function()
 local h=fixture(39);local roster=liveRoster(h);local check=safety(h);local main=h.env.ShirsRaidBuilderMainFrame
 h.C.PlannerQuoteInit();h:click(h:button(card(h,39),'X'));absent(h,'Visitor')
 assert(event(h,'RAID_ROSTER_UPDATE')>0 and event(h,'PARTY_MEMBERS_CHANGED')>0,'registered roster paths not exercised')
 for i=1,10 do h.env.RefreshComposition()end
 h.env.SlashCmdList.SHIRSRAIDBUILDER('');assert(not main:IsShown());h.env.SlashCmdList.SHIRSRAIDBUILDER('');absent(h,'Visitor')
 assert(h.env.GetRaidRosterInfo(2)=='Visitor' and table.getn(roster)==3,'plan removal changed synthetic live raid')
 h:click(main.plannerBtn);local planner=h.C.plannerFrame;h:click(planner.buildButton)
 assert(planner.proposal,planner.message:GetText());for _,e in ipairs(planner.proposal.plan.entries)do assert(e.charName~='Visitor','Build imported removed live human')end
 planner.nameInput:SetText('Without Visitor');h:click(planner.applyButton);absent(h,'Visitor')
 h:click(main.plannerBtn);h:click(planner.buildButton);assert(planner.proposal)
 planner.replaceCheck:SetChecked(1);h:fire(planner.replaceCheck,'OnClick');h:click(planner.applyButton)
 assert(planner.confirmFrame:IsShown(),'overwrite confirmation not exercised');h:click(h:button(planner.confirmFrame,'Replace'));absent(h,'Visitor')
 assert(h.env.ShirsRaidBuilderDB.currentPreset=='Without Visitor' and h:preset().entries[40].charName=='Tester')
 local serialized=dump(h.env.ShirsRaidBuilderDB);local fresh=boot(assert(loadstring('return '..serialized))());absent(fresh,'Visitor')
 assert(h.C.PlannerEqual(h:preset(),fresh:preset()),'fresh Lua environment changed saved plan');check()
 local output=os.getenv('SRB_HUMAN_RELOAD_OUT');if output then local file=assert(io.open(output,'w'));file:write('return '..serialized);file:close()end
end)

test('registered Refresh completes native trusted synchronization without importing an excluded live human',function()
 local file=assert(io.open('test_planner_linked_quotes.lua'));local source=file:read('*a');file:close()
 local boundary=assert(string.find(source,"\ntest('mixed own",1,true));local make=assert(loadstring(string.sub(source,1,boundary-1)..'\nreturn fixture'))()
 local a,b,c,pump=make();local p=a:preset();p.entries={}
 for i=1,40 do p.entries[i]={kind='empty'}end
 p.entries[1]={kind='normal',account='Alice',tier='t3r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'}
 p.entries[39]={kind='player',charName='Bob',class='warrior',role='tank'};p.entries[40]={kind='player',charName='Alice',class='warrior',role='tank'};p.plannerPlayerSlot=40
 a.env.RefreshComposition();local history=table.getn(a.history);local reads=table.getn(a.quoteReads)
 a.env.GetNumRaidMembers=function()return 2 end;a.env.GetRaidRosterInfo=function(i)if i==1 then return 'Alice',2,8,60,'Warrior'else return 'Bob',0,1,60,'Warrior'end end
 a:click(a:button(card(a,39),'X'));absent(a,'Bob')
 assert(table.getn(a.history)==history and table.getn(a.quoteReads)==reads,'Remove initiated transport')
 a:click(a.env.ShirsRaidBuilderMainFrame.syncButton);pump(30)
 assert(a.C.visiblePrice and a.C.visiblePrice.phase=='done' and a.C.visiblePrice.estimate.known==1,'native Refresh did not finish')
 absent(a,'Bob');a.env.RefreshComposition();absent(a,'Bob')
 local found=false;for _,s in ipairs(a.C.PlannerReadSources())do if s.name=='Bob'then found=true end end
 assert(found,'linked source vanished instead of remaining separate from plan occupancy')
 for _,h in ipairs({a,b,c})do assert(not h.C.handAuthority and not h.C.handRunPlan,'removal/Refresh granted hiring authority');for _,msg in ipairs(h.history)do assert(not h.C.HandParse(msg.text),'removal/Refresh sent a hiring handoff')end end
end)

test('Sort removal remains plan-only and explicit Capture can still replace that layout',function()
 local h=fixture(39);h:click(h.env.ShirsRaidBuilderMainFrame.modeBtn);local p=h.C.ActivePreset(h.env.ShirsRaidBuilderDB,'sort')
 p.entries[6]={kind='guest',charName='Visitor',companionName='Visitor',class='priest',role='healer'};h.env.RefreshComposition()
 local check=safety(h);h:click(h:button(card(h,6),'X'));assert(p.entries[6].kind=='empty');check()
 -- The existing explicit Sort Capture is deliberately still a replacement. No new Hire Capture is added.
 liveRoster(h);local queries=0
 h.env.SendAddonMessage=function(prefix,text,route)
  assert(prefix=='nexus' and text=='GRINFO:ALL:FULL' and route=='BATTLEGROUND','Capture emitted an unexpected action')
  queries=queries+1
 end
 h:click(h.env.ShirsRaidBuilderMainFrame.captureBtn);local prompt=h.env.ShirsRaidBuilderCaptureWarning
 assert(prompt and prompt:IsShown(),'explicit Capture warning missing')
 h:click(h:button(prompt,'Cancel'));assert(p.entries[6].kind=='empty','Capture Cancel changed the layout')
 h:click(h.env.ShirsRaidBuilderMainFrame.captureBtn);h:click(h:button(prompt,'Overwrite'))
 -- Drive the registered metadata-request timer, then deliver a synthetic valid reply.
 for _,w in ipairs(h.frames)do
  local fn=w:GetScript('OnUpdate')
  if fn then for i=1,32 do local name=debug.getupvalue(fn,i);if not name then break end;if name=='executeRequestFrame'then h:fire(w,'OnUpdate',0.25);break end end end
 end
 assert(queries==1,'Capture metadata request did not run exactly once')
 assert(event(h,'CHAT_MSG_ADDON','[nexus] GRINFO:ALL:FULL Companion:Human:Mage:rdps:Uncommon:Tester','nexus')>0)
 h:fire(h.C.sortFrame,'OnUpdate',0.25)
 local found=false;for _,e in ipairs(p.entries)do if e.charName=='Visitor'then found=true end end
 assert(found,'explicit Capture no longer replaces the layout from the roster')
end)

print("Shir's Raid Builder human removal tests: "..(fail==0 and 'PASS'or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
assert(fail==0,'human removal regressions failed')
