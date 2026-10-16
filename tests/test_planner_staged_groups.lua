-- Deterministic reservations before residual fill. Synthetic records, no live actions.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function dump(v)
 if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
 local keys,out={},{}; for k in pairs(v) do table.insert(keys,k) end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(v[k])) end; return '{'..table.concat(out,',')..'}'
end
local function row(class,role,kind,name,spec)
 return {kind=kind or 'normal',class=class,role=role,account=name or 'Alice',sourceName=name or 'Alice',charName=name or 'Alice',tier='t5r',spec=spec or 'default',race=class=='shaman' and 'orc' or 'human',gender='female'}
end
local function board() local e={}; for i=1,40 do e[i]={kind='empty'} end; return e end
local function group(entries,target) for i,e in ipairs(entries) do if e==target then return math.floor((i-1)/5)+1,i end end end
local function conserve(before,after)
 local bag={}; for _,e in ipairs(before) do local k=dump(e); bag[k]=(bag[k] or 0)+1 end
 for _,e in ipairs(after) do local k=dump(e); assert(bag[k] and bag[k]>0,'phantom/changed row'); bag[k]=bag[k]-1 end
 for _,n in pairs(bag) do assert(n==0,'dropped/duplicated row') end
end
local function firstFive(entries,n)
 for g=1,n do
  local count=0; for i=(g-1)*5+1,g*5 do if entries[i].class=='shaman' and C.IsFilledEntry(entries[i]) then count=count+1 end end
  assert(count==1 and entries[g*5].class=='shaman','Shaman reservation missing or stacked in group '..g)
 end
end

test('five mixed-role legacy/normal Shamans reserve 5 10 15 20 25 before filling',function()
 local e=board(); local shamans={}
 for i,role in ipairs({'healer','mdps','tank','rdps','healer'}) do local s=row('shaman',role,i==2 and 'legacy' or 'normal','Support'..string.char(64+i)); e[({1,11,16,23,29})[i]]=s; table.insert(shamans,s) end
 e[40]=row('warrior','tank','player','Self'); e[6]=row('mage','rdps','legacy','Caster','fire'); e[24]=row('druid','rdps','legacy','Balance')
 for _,i in ipairs({7,8,9,10}) do e[i]=row('warrior','tank','normal','Tank'..string.char(64+i)) end
 local before=C.PlannerCopy(e); local r=C.PlannerGroup(e,{[40]=true},8)
 firstFive(e,5); conserve(before,e); assert(e[40].kind=='player' and r.moves<=40)
end)

test('more than five Shamans cover remaining groups before any duplicate; fixed self40 is safe',function()
 for _,n in ipairs({1,3,5,6,8,9}) do
  local e=board(); for i=1,n do e[i]=row('shaman',i==2 and 'mdps' or 'healer',i==2 and 'legacy' or 'normal','Support'..string.char(64+i)) end
  e[40]=row('warrior','tank','player','Self'); local before=C.PlannerCopy(e); local r=C.PlannerGroup(e,{[40]=true},8)
  if n<=5 then firstFive(e,n) elseif n<=8 then firstFive(e,5) else for g=1,5 do assert(e[g*5].class=='shaman','extra support moved the first reservations') end end
  local counts={}; for i,v in ipairs(e) do if v.class=='shaman' then local g=math.floor((i-1)/5)+1; counts[g]=(counts[g] or 0)+1 end end
  if n>=8 then for g=1,8 do assert(counts[g] and counts[g]>=1,'stacked before covering group '..g) end end
  if n==8 then for g=1,8 do assert(counts[g]==1) end end
  if n>=8 then assert(e[40].kind=='player' and e[39].class=='shaman' and string.find(table.concat(r.notes or {},' '),'40',1,true),'rightmost human conflict not explained') end
  conserve(before,e)
 end
end)

test('fixed humans cause explicit rightmost/full-group conflicts without dropping support or anchors',function()
 local e=board(); local pins={}
 for i=1,5 do e[i]=row('priest','healer','guest','Human'..string.char(64+i)); pins[i]=true end
 e[10]=row('mage','rdps','guest','Fixed'); pins[10]=true
 for i=11,15 do e[i]=row('shaman','healer','normal','Support'..string.char(54+i)) end
 e[40]=row('warrior','tank','player','Self'); pins[40]=true
 local before=C.PlannerCopy(e); local r=C.PlannerGroup(e,pins,8)
 for i in pairs(pins) do assert(C.PlannerEqual(e[i],before[i]),'human anchor moved') end
 assert(e[9].class=='shaman','blocked rightmost did not use last safe slot')
 local notes=string.lower(table.concat(r.notes or {},' '))
 assert(string.find(notes,'group 1',1,true) and string.find(notes,'fixed',1,true) and string.find(notes,'10',1,true),'genuine anchor conflicts are silent')
 local counts={}; for i,v in ipairs(e) do if v.class=='shaman' then local g=math.floor((i-1)/5)+1; assert(not counts[g],'stacking despite other safe group'); counts[g]=true end end
 conserve(before,e)
end)

local f=assert(io.open('test_individual_editor.lua')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,'\nlocal failures, passes=',1,true)); local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))()
local function start()
 local entries=board(); entries[6]=row('mage','rdps','legacy','Echo','fire'); entries[11]=row('shaman','mdps','legacy','Delta'); entries[24]=row('druid','rdps','legacy','Foxtrot')
 entries[40]={kind='player',charName='Alice',class='warrior',role='tank'}
 local db={syncAccountId='1111111111111111',currentPreset='Default',presets={Default={entries=entries,denyRules={{class='priest',role='healer',abilities={'Holy Nova'}}},setupRules={}}},inviteCharacters={},legacyCharacters={echo='mage',delta='shaman',foxtrot='druid'},legacyCharacterRoles={echo='rdps',delta='mdps',foxtrot='rdps'}}
 for _,name in ipairs({'Alice','Bravo','Charlie','Delta','Echo','Foxtrot','Golf','Hotel'}) do db.inviteCharacters[name]={name=name,level=60,dungeonLicense='t5d',raidLicense='t5r',faction=name=='Delta' and 'Horde' or 'Alliance'} end
 local h=boot(db,'Alice'); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn); local p=h.C.plannerFrame
 for _,r in ipairs(p.sourceRows) do
  r.normalCheck:SetChecked(1); h:fire(r.normalCheck,'OnClick')
  if r.source.name=='Echo' or r.source.name=='Delta' or r.source.name=='Foxtrot' then r.legacyCheck:SetChecked(1); h:fire(r.legacyCheck,'OnClick') end
 end
 h:click(h:button(p,'Composition'))
 for key,n in pairs({['warrior:tank']=4,['warrior:mdps']=4,['shaman:healer']=4,['mage:rdps']=4,['warlock:rdps']=4,['priest:healer']=4,['paladin:healer']=4}) do p.countInputs[key]:SetText(tostring(n)) end
 return h,p
end
local function assertComposition(h,r)
 local notes=table.concat(r.notes,' ')
 assert(string.find(notes,'Shaman reservations',1,true) and string.find(notes,'legacy companions regroup',1,true),'preview still describes fixed legacy slots or purely soft support placement')
 local entries=r.plan.entries; firstFive(entries,5)
 local mage,balance,tanks,legacies=nil,nil,{},0
 for i,e in ipairs(entries) do
  if e.kind=='legacy' then legacies=legacies+1; if e.class=='mage' then mage=i; assert(e.sourceName=='Echo' and e.spec=='fire' and h.C.BuildHireCommand(e)=='.z addlegacy "Echo" rdps fire') elseif e.class=='druid' then balance=i end end
  if e.kind=='normal' and e.class=='warrior' and e.role=='tank' then table.insert(tanks,i) end
 end
 assert(legacies==3 and mage and balance and math.floor((mage-1)/5)==math.floor((balance-1)/5),'legacy Mage and Balance were stranded by old anchors')
 assert(table.getn(tanks)==4); local tg=math.floor((tanks[1]-1)/5)
 for _,i in ipairs(tanks) do assert(math.floor((i-1)/5)==tg and i<=20,'Warrior tanks needlessly split') end
 assert(math.floor((mage-1)/5)~=tg,'Mage remained among Warrior tanks despite caster room')
 assert(entries[40].charName=='Alice' and entries[40].kind=='player' and r.normal==28 and r.total==32)
end

test('registered Build Create Refresh reload retain the staged constraints and exact complete multiset',function()
 local h,p=start(); local base=dump(h:preset()); h:click(p.buildButton); local r=assert(p.proposal,p.message:GetText()); assertComposition(h,r)
 local expected=dump(r.plan.entries); local again=h.C.PlannerBuild(p.base,p.sources,p.request); assert(expected==dump(again.plan.entries),'repeat build not deterministic')
 p.nameInput:SetText('Staged'); h:click(p.applyButton); assert(h.env.ShirsRaidBuilderDB.currentPreset=='Staged' and expected==dump(h:preset().entries),'Create/refresh mutated slots')
 assert(base==dump(h.env.ShirsRaidBuilderDB.presets.Default),'source profile changed')
 h.env.RefreshComposition(); assert(expected==dump(h:preset().entries))
 local restored=boot(assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))(),'Alice'); assert(expected==dump(restored:preset().entries),'reload mutated groups')
 restored:click(restored.env.ShirsRaidBuilderMainFrame.plannerBtn); local nextp=restored.C.plannerFrame; restored:click(nextp.buildButton)
 assert(nextp.proposal and expected==dump(nextp.proposal.plan.entries),'rebuild saved plan changed groups')
end)

test('insufficient casters give a clear limit and never invent another row',function()
 local e=board(); e[24]=row('druid','rdps','legacy','Balance'); e[40]=row('warrior','tank','player','Self')
 local before=C.PlannerCopy(e); local r=C.PlannerGroup(e,{[40]=true},8)
 conserve(before,e); assert(string.find(string.lower(table.concat(r.notes or {},' ')),'caster',1,true),'missing caster supply not explained')
end)
test('full forty-row heldout board conserves all metadata with staged support caster pair and tanks',function()
 local e=board(); local at=1
 local function add(v) e[at]=v; at=at+1 end
 for i=1,5 do add(row('shaman',i==2 and 'mdps' or 'healer',i==2 and 'legacy' or 'normal','Support'..string.char(64+i))) end
 for i=1,4 do add(row('warrior','tank','normal','Tank'..string.char(64+i))) end
 local balance=row('druid','rdps','legacy','Balance'); local mage=row('mage','rdps','legacy','Caster','fire'); mage.denyList={'Frost Nova'}; mage.whisperName='Caster-lite'
 add(balance); add(mage)
 for i=1,8 do local v=row(i<=4 and 'mage' or 'warlock','rdps','normal','Ranged'..string.char(64+i),'fire'); v.tier=i<=4 and 't3r' or 't5r'; add(v) end
 for i=1,4 do add(row(i<=2 and 'paladin' or 'druid','mdps','normal','Melee'..string.char(64+i))) end
 for i=1,16 do add(row(math.mod(i,2)==0 and 'paladin' or 'priest','healer','normal','Healer'..string.char(64+i))) end
 assert(at==40); e[40]=row('warrior','tank','player','Self')
 local before=C.PlannerCopy(e); C.PlannerGroup(e,{[40]=true},8); conserve(before,e); firstFive(e,5)
 local mg=group(e,mage); assert(mg==group(e,balance),'full-board caster pair split')
 local tg
 for i,v in ipairs(e) do
  local g=math.floor((i-1)/5)+1
  if v.kind=='normal' and v.class=='warrior' and v.role=='tank' then tg=tg or g; assert(tg==g and g<=4,'full-board tanks split') end
 end
 assert(mg~=tg and e[40].kind=='player')
 for i=(tg-1)*5+1,tg*5 do assert(e[i].class~='mage' and e[i].class~='warlock','caster stuck with tanks despite caster capacity') end
 local expected=dump(e); C.PlannerGroup(e,{[40]=true},8); assert(dump(e)==expected,'grouping not stable on repeated full board')
end)

test('full human anchors explain impossible caster pair without moving humans or inventing capacity',function()
 local e=board(); local pins={}
 for g=1,8 do for i=(g-1)*5+1,g*5-1 do e[i]=row('priest','healer','guest','Human'..string.char(64+i)); pins[i]=true end end
 e[40]=row('warrior','tank','player','Self'); pins[40]=true
 for g=1,5 do e[g*5]=row('shaman','healer','normal','Support'..string.char(64+g)) end
 e[30]=row('druid','rdps','legacy','Balance'); e[35]=row('mage','rdps','legacy','Caster','fire')
 local before=C.PlannerCopy(e); local r=C.PlannerGroup(e,pins,8); conserve(before,e); firstFive(e,5)
 for i in pairs(pins) do assert(C.PlannerEqual(e[i],before[i]),'fixed human moved to satisfy companion preference') end
 assert(string.find(string.lower(table.concat(r.notes or {},' ')),'capacity',1,true),'impossible caster pair hidden behind score')
end)

test('fixed Balance can receive movable legacy Mage in its one remaining slot',function()
 local e=board(); local pins={[21]=true,[22]=true,[23]=true,[24]=true,[40]=true}
 e[21]=row('druid','rdps','guest','Balance'); e[22]=row('priest','healer','guest','Humanone'); e[23]=row('paladin','healer','guest','Humantwo'); e[24]=row('priest','healer','guest','Humanthree')
 e[40]=row('warrior','tank','player','Self'); local mage=row('mage','rdps','legacy','Caster','fire'); e[6]=mage
 local before=C.PlannerCopy(e); C.PlannerGroup(e,pins,8); conserve(before,e); assert(e[25]==mage,'single free slot failed to receive legacy caster')
 for i in pairs(pins) do assert(C.PlannerEqual(e[i],before[i])) end
end)

test('a sparse old legacy slot cannot escape the new compact proposal group range',function()
 local e=board(); local legacy=row('mage','rdps','legacy','Caster','fire'); legacy.denyList={'Frost Nova'}; e[40]=legacy
 local base={entries=e,denyRules={},setupRules={}}
 local r=assert(C.PlannerBuild(base,{}, {counts={},sources={}})); assert(r.total==1 and r.legacy==1 and r.groups==1)
 local seen=0
 for i,v in ipairs(r.plan.entries) do if C.IsFilledEntry(v) then assert(i<=r.groups*5,'unlocked old legacy remained outside proposed groups'); assert(C.PlannerEqual(v,legacy)); seen=seen+1 end end
 assert(seen==1 and base.entries[40]==legacy,'legacy identity or input changed')
 local again=assert(C.PlannerBuild(r.plan,{}, {counts={},sources={}})); assert(dump(again.plan.entries)==dump(r.plan.entries),'sparse saved legacy rebuild changed layout')
end)

print("Shir's Raid Builder staged grouping tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('staged grouping regressions failed') end
