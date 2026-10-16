-- Complete Balance reservation before residual physical/healer filling.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua');local C=ShirsRaidBuilderCore
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local function row(class,role,kind,name,spec)return {kind=kind or 'normal',class=class,role=role,sourceName=name or 'Source',charName=name or 'Source',account=name or 'Source',tier='t3r',spec=spec or 'default',race=class=='shaman' and 'orc' or 'human',gender='female',denyList={}} end
local function dump(v)if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end;local parts={};for k,x in pairs(v) do table.insert(parts,'['..dump(k)..']='..dump(x)) end;table.sort(parts);return '{'..table.concat(parts,',')..'}' end
local function group(entries,target)for i,e in ipairs(entries) do if e==target then return math.floor((i-1)/5)+1 end end end
local function bag(entries)local out={};for _,e in ipairs(entries) do local k=dump(e);out[k]=(out[k] or 0)+1 end;return dump(out) end
local function assertBlock(entries,balance,primary,fires,locks)
 local g=assert(group(entries,balance));assert(group(entries,primary)==g,'primary legacy caster split')
 local fire,lock,n=0,0,0
 for i=(g-1)*5+1,g*5 do local e=entries[i];if C.IsFilledEntry(e) then n=n+1 end;if e~=primary then if e.class=='mage' and e.role=='rdps' and e.spec=='fire' then fire=fire+1 elseif e.class=='warlock' and e.role=='rdps' then lock=lock+1 end end end
 assert(fire==fires and lock==locks,'incomplete Balance extras: Fire '..fire..', Warlocks '..lock)
 assert(n==5 and entries[g*5].class=='shaman','full five-member caster block/Shaman lost')
 return g
end
local function full(fires,physical)
 local entries={};local function add(e)table.insert(entries,e);return e end
 for i=1,5 do add(row('shaman','healer','normal','Support'..string.char(64+i))) end
 for i=1,4 do add(row('warrior','tank','normal','Tank'..string.char(64+i))) end
 for i=1,(physical or 8) do add(row('warrior','mdps','normal','Melee'..string.char(64+i))) end
 local balance=add(row('druid','rdps','legacy','Balance'));local primary=add(row('mage','rdps','legacy','Primary','fire'))
 for i=1,fires do add(row('mage','rdps','normal','Fire'..string.char(64+i),'fire')) end
 for i=1,4 do add(row('warlock','rdps','normal','Lock'..string.char(64+i))) end
 -- Unknown/Auto/Frost mages are never Fire substitutions.
 add(row('mage','rdps','normal','Unknown','default'))
 while table.getn(entries)<39 do add(row('priest','healer','normal','Healer'..string.char(64+table.getn(entries)))) end
 assert(table.getn(entries)==39);add(row('warrior','tank','player','Self'))
 return entries,balance,primary
end
for fires=0,2 do local fireCount=fires
 test('full requested caster block with '..fireCount..' known Fire extras and per-slot Warlock fallback',function()
  local e,b,m=full(fireCount);local before=bag(e);local r=C.PlannerGroup(e,{[40]=true},8);assertBlock(e,b,m,fireCount,2-fireCount);assert(before==bag(e) and e[40].charName=='Self','row multiset/human anchor changed')
  for g=1,5 do assert(e[g*5].class=='shaman') end
  local expected=dump(e);C.PlannerGroup(e,{[40]=true},8);assert(expected==dump(e),'repeat grouping unstable')
 end)
end
local raw=assert(io.open('test_individual_editor.lua'));local text=raw:read('*a');raw:close();local at=assert(string.find(text,'\nlocal failures, passes=',1,true))
-- The pure Core suite above owns a global table. Each full-module boot must
-- shadow it so a second environment cannot reuse the prior environment's UI.
text=string.gsub(string.sub(text,1,at-1),'local env = {};','local env = {ShirsRaidBuilderCore={}};')
local boot=assert(loadstring(text..'\nreturn boot'))()
for _,knownFire in ipairs({0,1,2}) do
local selectedFire=knownFire
test('registered Build Create Refresh fresh Lua reload keeps complete caster block with '..selectedFire..' known Fire extras',function()
 local entries={};for i=1,40 do entries[i]={kind='empty'} end
 entries[6]={kind='legacy',sourceName='Echo',charName='Echo',class='mage',role='rdps',spec='frost',denyList={'Frost Nova'},whisperName='Echo-lite'}
 entries[11]={kind='legacy',sourceName='Delta',charName='Delta',class='shaman',role='mdps',denyList={}}
 entries[24]={kind='legacy',sourceName='Foxtrot',charName='Foxtrot',class='druid',role='rdps',denyList={}}
 entries[40]={kind='player',charName='Alice',class='warrior',role='tank'}
 local db={syncAccountId='1111111111111111',currentPreset='Default',presets={Default={entries=entries,denyRules={{class='priest',role='healer',abilities={'Holy Nova'}}},setupRules={}}},inviteCharacters={},legacyCharacters={echo='mage',delta='shaman',foxtrot='druid'},legacyCharacterRoles={echo='rdps',delta='mdps',foxtrot='rdps'}}
 for _,name in ipairs({'Alice','Bravo','Charlie','Delta','Echo','Foxtrot','Golf','Hotel'}) do db.inviteCharacters[name]={name=name,level=60,dungeonLicense='t5d',raidLicense='t5r',faction=name=='Delta' and 'Horde' or 'Alliance'} end
 local h=boot(db,'Alice');h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);local p=h.C.plannerFrame
 for _,r in ipairs(p.sourceRows) do r.normalCheck:SetChecked(1);h:fire(r.normalCheck,'OnClick') end
 h:click(h:button(p,'Composition'));h:choose(p.classDefaults.mage.specButton,selectedFire>0 and 'fire' or 'frost')
 for k,n in pairs({['warrior:tank']=4,['warrior:mdps']=4,['shaman:healer']=4,['mage:rdps']=selectedFire>0 and selectedFire or 4,['warlock:rdps']=4,['priest:healer']=4,['paladin:healer']=4}) do p.countInputs[k]:SetText(tostring(n)) end
 local original=dump(h:preset());h:click(p.buildButton);local proposal=assert(p.proposal,p.message:GetText());local b,m
 for _,e in ipairs(proposal.plan.entries) do if e.kind=='legacy' and e.class=='druid' then b=e elseif e.kind=='legacy' and e.class=='mage' then m=e end end
 assertBlock(proposal.plan.entries,b,m,selectedFire,2-selectedFire);local expected=dump(proposal.plan.entries);local queue=dump(h.C.BuildQueue(proposal.plan))
 p.nameInput:SetText('Complete caster block');h:click(p.applyButton);assert(expected==dump(h:preset().entries) and original==dump(h.env.ShirsRaidBuilderDB.presets.Default),'Create changed identities/source plan')
 h.env.RefreshComposition();assert(expected==dump(h:preset().entries) and queue==dump(h.C.BuildQueue(h:preset())))
 local fresh=boot(assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))(),'Alice');assert(expected==dump(fresh:preset().entries),'reload changed caster block')
end)
end
test('legacy Warlock primary fallback and scarce multiple Balance groups conserve identities and explain compromise',function()
 local entries,b,m=full(1);m.class='warlock';m.spec='default';local before=bag(entries)
 C.PlannerGroup(entries,{[40]=true},8);assertBlock(entries,b,m,1,1);assert(before==bag(entries))
 entries,b,m=full(0)
 for _,e in ipairs(entries) do if e.class=='warlock' then e.class='priest';e.role='healer' end end
 entries[39]=row('druid','rdps','legacy','Secondbalance');before=bag(entries)
 local r=C.PlannerGroup(entries,{[40]=true},8);assert(before==bag(entries) and string.find(table.concat(r.notes,' '),'of two additional',1,true),'scarce caster compromise hidden')
 local first=dump(entries);C.PlannerGroup(entries,{[40]=true},8);assert(first==dump(entries),'multiple Balance compromise nondeterministic')
end)
print("Shir's Raid Builder complete caster tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'complete caster regressions failed')
