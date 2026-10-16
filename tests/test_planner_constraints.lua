-- Staged physical/caster reservations and packing; synthetic Lua50 only.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local passed,failed=0,0
local function test(name,fn) local ok,e=pcall(fn);if ok then passed=passed+1;print('PASS '..name) else failed=failed+1;print('FAIL '..name..': '..tostring(e)) end end
local function board() local e={};for i=1,40 do e[i]={kind='empty'} end;e[40]={kind='player',charName='Self',class='warrior',role='tank'};return e end
local serial=0
local function row(class,role,kind) serial=serial+1;return {kind=kind or 'normal',class=class,role=role,account='Source'..serial,sourceName='Source'..serial,tier='t5r',spec='default',denyList={'Ability '..serial}} end
local function g(e,target) for i,v in ipairs(e) do if v==target then return math.floor((i-1)/5)+1,i end end end
local function add(e,v) for i=1,39 do if e[i].kind=='empty' then e[i]=v;return v end end;error('full fixture') end
local function conserve(before,e) local seen={};for _,v in ipairs(before) do seen[v]=(seen[v] or 0)+1 end;for _,v in ipairs(e) do assert(seen[v] and seen[v]>0,'changed/phantom row');seen[v]=seen[v]-1 end;for _,n in pairs(seen) do assert(n==0,'lost/duplicated row') end end
local function run(e,pins) local old={};for i,v in ipairs(e) do old[i]=v end;local r=C.PlannerGroup(e,pins or {[40]=true},8);conserve(old,e);assert(e[40]==old[40]);return r end
local function pack(e)
 local n=0;for _,v in ipairs(e) do if C.IsFilledEntry(v) then n=n+1 end end
 for i=1,n-1 do assert(C.IsFilledEntry(e[i]),'avoidable hole at '..i) end
 for i=n,39 do assert(not C.IsFilledEntry(e[i]),'late occupant at '..i) end
end
local function support(e,n,normal) for i=1,n do add(e,row('shaman','healer',i<=normal and 'normal' or 'legacy')) end end
local function synergy(e)
 support(e,5,4);for i=1,4 do add(e,row('warrior','tank')) end
 local h=add(e,row('hunter','rdps','legacy'));local r=add(e,row('rogue','mdps','legacy'));local d=add(e,row('druid','tank'))
 local w=add(e,row('warrior','mdps'));local old=add(e,row('warrior','mdps','legacy'))
 return h,r,d,w,old
end

test('Group2 Hunter Rogue bear and NORMAL Warrior with normal Shaman10',function()
 local e=board();local h,r,d,w,old=synergy(e);run(e)
 for _,v in ipairs({h,r,d,w}) do assert(g(e,v)==2,'requested Group2 member omitted') end
 assert(g(e,old)~=2 and e[10].class=='shaman' and e[10].kind=='normal')
 for i=1,4 do assert(e[i].class=='warrior' and e[i].role=='tank') end
end)
test('sole normal Shaman reserves Group2 before greedy group1; legacy fallback is safe',function()
 for _,normal in ipairs({1,0}) do local e=board();support(e,5,normal);local r=run(e);assert(e[10].kind==(normal==1 and 'normal' or 'legacy'));for g=1,5 do assert(e[g*5].class=='shaman') end end
end)
test('Group2 prefers feral over bear deterministically without Balance/healer confusion',function()
 local e=board();local h,r,b,w=synergy(e);local feral=add(e,row('druid','mdps'));local balance=add(e,row('druid','rdps'));local healer=add(e,row('druid','healer'));run(e)
 assert(g(e,feral)==2 and g(e,b)~=2 and g(e,balance)~=2 and g(e,healer)~=2)
 assert(C.PlannerBucket(h)=='rdps' and not C.PlannerPhysical(balance) and not C.PlannerPhysical(healer))
end)
test('absent normal Warrior reports unmet coverage instead of calling legacy a substitute',function()
 local e=board();support(e,5,4);add(e,row('hunter','rdps'));add(e,row('rogue','mdps'));add(e,row('druid','mdps'));add(e,row('warrior','mdps','legacy'))
 local r=run(e);assert(string.find(string.lower(table.concat(r.notes,' ')),'normal warrior',1,true),'missing normal coverage silent')
end)
test('fixed human blocks Group2 preference without moving anchor',function()
 local e=board();local h,r,d,w=synergy(e);local fixed=row('mage','rdps','guest');e[6]=fixed
 local result=run(e,{[6]=true,[40]=true});assert(e[6]==fixed and string.find(string.lower(table.concat(result.notes,' ')),'group 2',1,true))
end)
test('physical fills spare Group1 and earliest groups before unrelated casters',function()
 local e=board();support(e,5,5);add(e,row('warrior','tank'));for i=1,7 do add(e,row(i==1 and 'hunter' or 'rogue',i==1 and 'rdps' or 'mdps')) end
 for i=1,15 do add(e,row('mage','rdps')) end;for i=1,6 do add(e,row('paladin','healer')) end;run(e)
 for i=1,4 do assert(C.PlannerPhysical(e[i]),'spare group1 wasted') end
 for i=1,20 do if e[i].class=='mage' then for j=i+1,39 do assert(not (C.PlannerPhysical(e[j]) and e[j].class~='shaman'),'physical stranded behind caster') end end end
end)
for _,holes in ipairs({2,3}) do
 local gaps=holes
 test('tail packing leaves '..gaps..' empties immediately before self40 and keeps caster reservations',function()
  local e=board();support(e,5,4);for i=1,4 do add(e,row('warrior','tank')) end
  local balance=add(e,row('druid','rdps','legacy'));local mage=add(e,row('mage','rdps','legacy'));local shadow=add(e,row('priest','rdps','legacy'))
  for i=1,4 do add(e,row('warlock','rdps',i==1 and 'legacy' or 'normal')) end
  while true do local n=0;for _,v in ipairs(e) do if C.IsFilledEntry(v) then n=n+1 end end;if n>=40-gaps then break end;add(e,row(n<24 and 'rogue' or 'paladin',n<24 and 'mdps' or 'healer')) end
  run(e);pack(e);assert(g(e,balance)==g(e,mage));local sg=g(e,shadow);local locks=0;for i=(sg-1)*5+1,sg*5 do if e[i].class=='warlock' then locks=locks+1 end end;assert(locks==2,'Shadow must receive the two Warlocks left after the complete Balance block');local bg=g(e,balance);local extra=0;for i=(bg-1)*5+1,bg*5 do if e[i].class=='warlock' then extra=extra+1 end end;assert(extra==2,'Balance did not reserve both non-Fire substitutions')
  for g=1,5 do assert(e[g*5].class=='shaman') end
 end)
end
for _,n in ipairs({0,1,2,4,6}) do
 local locks=n
 test('Shadow Priest maximizes supplied Warlocks with '..locks..' locks and no extra hires',function()
  local e=board();local shadow=add(e,row('priest','rdps','legacy'));for i=1,locks do add(e,row('warlock','rdps',i==1 and 'legacy' or 'normal')) end
  for i=1,8 do add(e,row('mage','rdps')) end
  run(e);local sg=g(e,shadow);local count=0;for i=(sg-1)*5+1,sg*5 do if e[i].class=='warlock' then count=count+1 end end;assert(count==math.min(locks,4),'did not reserve feasible Shadow group');pack(e)
 end)
end
test('multiple Shadow Priests deterministic first identity takes locks; healer is excluded',function()
 local e=board();local first=add(e,row('priest','rdps'));local second=add(e,row('priest','rdps'));local heal=add(e,row('priest','healer'));for i=1,5 do add(e,row('warlock','rdps')) end;for i=1,10 do add(e,row('mage','rdps')) end
 run(e);assert(g(e,first)~=g(e,second));local counts={};for _,p in ipairs({first,second}) do local sg=g(e,p);local n=0;for i=(sg-1)*5+1,sg*5 do if e[i].class=='warlock' then n=n+1 end end;table.insert(counts,n) end;table.sort(counts);assert(counts[1]==1 and counts[2]==4);assert(heal.role=='healer')
end)
for _,spare in ipairs({1,2}) do
 local free=spare
 test('last physical DPS group uses Paladin then Priest with '..free..' spare',function()
  local e=board();support(e,3,3);for i=1,4 do add(e,row('warrior','tank')) end
  for i=1,4+(4-free) do add(e,row('rogue','mdps')) end
  local pal=add(e,row('paladin','healer'));local priest=add(e,row('priest','healer'));for i=1,12 do add(e,row('mage','rdps')) end
  run(e);assert(g(e,pal)==3,'last physical group missed Paladin first');if free==2 then local _,pi=g(e,pal);local _,ri=g(e,priest);assert(g(e,priest)==3 and pi<ri,'Priest not second filler') end
 end)
end
test('missing Paladin uses supplied Priest; full physical group remains unchanged',function()
 for _,count in ipairs({7,8}) do local e=board();support(e,3,3);for i=1,4 do add(e,row('warrior','tank')) end;for i=1,count do add(e,row('rogue','mdps')) end;local priest=add(e,row('priest','healer'));for i=1,12 do add(e,row('mage','rdps')) end;run(e);assert((g(e,priest)==3)==(count==7)) end
end)
test('genuine fixed-anchor suffix conflict is explained and never moves humans',function()
 local e=board();e[39]=row('mage','rdps','guest');for i=1,7 do add(e,row('mage','rdps')) end
 local r=run(e,{[39]=true,[40]=true});assert(e[39].kind=='guest');assert(string.find(string.lower(table.concat(r.notes,' ')),'fixed',1,true))
end)
print("Shir's Raid Builder planner constraint tests: "..(failed==0 and 'PASS' or 'FAIL')..' ('..passed..' passed, '..failed..' failed)')
assert(failed==0,'planner constraint regressions failed')
