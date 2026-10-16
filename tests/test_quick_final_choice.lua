-- Actual registered Quick Hire handlers, exact Lua 5.0.3; no game input/chat.
local file=assert(io.open('test_quick_hire.lua','r')); local source=file:read('*a'); file:close()
local at=assert(string.find(source,"\ntest('Random Tank",1,true))
local helper=assert(loadstring(string.sub(source,1,at-1)..'\nreturn {start=start,saved=saved}'))()
local start,saved=helper.start,helper.saved
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function count(h)
 local n=0; for _,e in ipairs(h:preset().entries) do if e.kind=='normal' then n=n+1 end end; return n
end
local function open(h,branch,tier,index)
 local q=h:quick(index or 9); h:choose(q.sourceButton,'Alice'); if tier then h:choose(q.tierButton,tier) end
 h:click(h:button(q,branch)); return q
end
local function dump(v)
 if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
 local keys,out={},{}; for k in pairs(v) do table.insert(keys,k) end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(v[k])) end; return '{'..table.concat(out,',')..'}'
end

test('Random final role adds one row, retains role choices and advances without Add or reopen',function()
 local h=start(); local p=h:preset(); p.entries[10]={kind='guest',companionName='Occupied',class='mage',role='rdps'}
 local q=open(h,'Random','t1r'); local button=h:button(q,'Tank')
 assert(count(h)==0); h:click(button)
 assert(count(h)==1 and p.entries[9].class=='random' and p.entries[9].role=='tank','final Random role still needs Add')
 assert(h.C.BuildNormalHireCommand(p.entries[9])=='.z addi Alice t1r tank')
 assert(q:IsVisible() and q.slot==11 and string.find(q.title:GetText(),'11',1,true),'next empty target not visible')
 assert(q.sourceButton.label:GetText()=='Alice' and q.tierButton.label:GetText()=='t1r' and q.tierChosen)
 h:fire(button,'OnClick'); assert(count(h)==1,'stale handler replay inserted twice')
 h:click(h:button(q,'Tank')); assert(count(h)==2 and p.entries[11].role=='tank' and q.slot==12,'intentional same role click cannot add next')
 h.C.QuickHirePage(); assert(count(h)==2,'refresh inserted a row')
 h:choose(q.sourceButton,'Hordealt'); h:choose(q.tierButton,'t0d'); assert(count(h)==2,'source/tier edits inserted')
 h:click(h:button(q,'Healer')); assert(count(h)==3 and p.entries[12].account=='Hordealt' and p.entries[12].tier=='t0d')
 local before=dump(p); h:click(h:button(q,'Cancel')); assert(dump(p)==before and p.entries[10].kind=='guest')
end)

test('Class waits for explicit required choices then final selector adds exactly one and can repeat',function()
 local h=start(); local q=open(h,'Class','t2d'); h:click(h:button(q,'DPS')); h:click(h:button(q,'Mage'))
 assert(count(h)==0,'class defaults bypassed required choices')
 h:choose(q.raceButton,'Gnome'); assert(count(h)==0,'race alone bypassed remaining choices')
 h:choose(q.genderButton,'Female'); assert(count(h)==0,'gender bypassed spec choice')
 h:click(q.specButton); local option=h:button(h.env.ShirsRaidBuilderChoiceMenu,'Fire'); h:click(option)
 assert(count(h)==1 and q.slot==10 and q:IsVisible(),'final Class spec still needs Add')
 local e=h:preset().entries[9]; assert(e.class=='mage' and e.spec=='fire' and e.race=='gnome' and e.gender=='female' and e.tier=='t2d')
 h:fire(option,'OnClick'); assert(count(h)==1,'one Class option fired twice')
 h:choose(q.specButton,'Fire'); assert(count(h)==2 and h:preset().entries[10].spec=='fire','same final Class option cannot intentionally add next')
 h:choose(q.sourceButton,'Hordealt'); assert(count(h)==2 and not q.tierChosen)
 h:choose(q.tierButton,'t1r'); assert(count(h)==2,'tier change auto-added')
 h:choose(q.specButton,'Fire'); assert(count(h)==2,'invalidated race was implicitly confirmed')
 h:choose(q.raceButton,'Troll'); assert(count(h)==3 and h:preset().entries[11].account=='Hordealt')
end)

test('Random explicit-tier, source cap, full board and stale context guards apply to final-role handlers',function()
 local h=start(); local q=open(h,'Random')
 h:click(h:button(q,'Tank')); assert(count(h)==0,'missing explicit tier auto-added')
 h:choose(q.tierButton,'t1r'); assert(count(h)==0,'tier choice auto-added')
 for i=1,4 do h:click(h:button(q,'Tank')); assert(count(h)==i) end
 h:click(h:button(q,'Tank')); assert(count(h)==4 and q:IsVisible() and string.find(q.note:GetText(),'four',1,true))
 h:choose(q.sourceButton,'Hordealt'); assert(count(h)==4); h:click(h:button(q,'DPS')); assert(count(h)==5)
 h=start(); local p=h:preset(); for i=2,39 do p.entries[i]={kind='guest',companionName='Occupied',class='mage',role='rdps'} end
 q=open(h,'Random','t1r',40); h:click(h:button(q,'Healer')); assert(count(h)==1 and not q.slot and q:IsVisible())
 local before=dump(p); h:click(h:button(q,'Healer')); assert(dump(p)==before and string.find(q.note:GetText(),'40',1,true))
 for _,guard in ipairs({'profile','entries','slot','player','realm','run','mode'}) do
  h=start(); q=open(h,'Random','t1r'); local target=h:button(q,'Tank')
  if guard=='profile' then h.env.ShirsRaidBuilderDB.presets.Default={entries={},denyRules={},setupRules={}}
  elseif guard=='entries' then h:preset().entries={}
  elseif guard=='slot' then h:preset().entries[9]={kind='guest',companionName='Occupied',class='mage',role='rdps'}
  elseif guard=='player' then h.env.UnitName=function() return 'Other' end
  elseif guard=='realm' then h.env.GetRealmName=function() return 'OtherRealm' end
  elseif guard=='run' then h.C.handAuthority='active'
  else h.env.ShirsRaidBuilderDB.uiMode='sort' end
  before=dump(h.env.ShirsRaidBuilderDB.presets); h:click(target)
  assert(dump(h.env.ShirsRaidBuilderDB.presets)==before and not q:IsVisible(),'final-role bypassed '..guard..' guard')
 end
end)

test('obsolete top status is absent; planner owns original area and essential footer/Stop feedback survives',function()
 local h=start(); local main=h.env.ShirsRaidBuilderMainFrame
 assert(main.handProgress==nil,'persistent top Hire status caption still constructed')
 assert(main.plannerBtn and main.plannerBtn.point[4]==310 and main.plannerBtn.point[5]==-8,'planner lost reclaimed original status area')
 local footer
 for _,w in ipairs(main.fonts) do
  assert(not (w.point and w.point[1]=='TOPLEFT' and w.point[4]==80 and w.point[5]==-32),'blank former-status reservation remains')
  if w.point and w.point[1]=='BOTTOMLEFT' and w.point[4]==22 and w.point[5]==16 then footer=w end
 end
 local why='Paused: source unavailable. Refresh Synchronization, then Stop before Execute.'
 h.C.HandStatus(why); assert(footer and footer:GetText()==why and string.find(main.stopBtn.tip,why,1,true))
 h:click(main.plannerBtn); assert(h.env.ShirsRaidBuilderPlanner:IsVisible(),'new builder displaced by removed status')
 h:click(h:button(h.env.ShirsRaidBuilderPlanner,'Cancel'))
 assert(footer:GetText()==why and main.handProgress==nil)
 h.env.ShirsRaidBuilderDB.quietMode=true; h.C.HandStatus(why)
 assert(footer:GetText()==why and string.find(main.stopBtn.tip,why,1,true),'Quiet hid essential recovery')
end)

print("Shir's Raid Builder quick final choice tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('quick final choice regressions failed') end
