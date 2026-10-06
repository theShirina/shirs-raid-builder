dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local rows={{name='Alpha',raidLicense='t1r',realm='Z'},{name='Zulu',raidLicense='t5r'},
 {name='Beta',raidLicense='t4r'},{name='Missing'},{name='Unknown',raidLicense='unknown'},
 {name='None',raidLicense='none'},{name='Alpha',raidLicense='t1r',realm='A'},
 {name='Second',raidLicense='t2r'},{name='Invalid',raidLicense='t9r'}}
assert(type(C.AccountLicenseOrder)=='function','descending license comparator missing')
local sorted=C.AccountLicenseOrder(rows)
assert(sorted[1].name=='Zulu' and sorted[2].name=='Beta' and sorted[3].name=='Second')
assert(sorted[4].realm=='A' and sorted[5].realm=='Z','stable name/realm ties')
assert(sorted[6].name=='None' and sorted[7].name=='Invalid' and sorted[8].name=='Missing' and sorted[9].name=='Unknown')
assert(rows[1].name=='Alpha','sort mutated source')
local plan={entries={{kind='normal',account='Alice',class='mage',role='rdps',spec='default',tier='t2r',race='human',gender='female',denyList={'Fireball'}},
 {kind='empty'},{kind='legacy',charName='Companion',sourceName='Companion',class='warrior',role='tank',setup={pet='imp'}}},denyRules={{ability='Danger'}},setupRules={{pet='imp'}}}
assert(type(C.PlanEncode)=='function','bounded plan codec missing')
local wire=assert(C.PlanEncode(plan,'hire','Current raid'))
assert(not string.find(wire,'Fireball',1,true) and not string.find(wire,'Danger',1,true) and not string.find(wire,'imp',1,true),'settings crossed boundary')
local copy=assert(C.PlanDecode(wire)); assert(copy.mode=='hire' and copy.name=='Current raid')
assert(copy.entries[1].account=='Alice' and copy.entries[2].kind=='empty' and copy.entries[3].sourceName=='Companion')
assert(not copy.entries[1].denyList and not copy.setupRules and not copy.denyRules)
assert(not C.PlanDecode(wire..'/bad') and not C.PlanDecode(string.rep('x',6145)))
assert(not C.PlanEncode({entries={[41]={kind='empty'}}},'hire','Bad'))
assert(not C.PlanEncode({entries={{kind='normal',account='Alice;EXECUTE'}}},'hire','Bad'))
local now=1800000000
local a=C.PeerNew('Alice','Bob','Realm'); a.phase='linked'; a.a='100001'; a.b='100002'; a.started=10; a.deadline=70; a.expires=now+60
local function receiver()
 local b=C.PeerNew('Bob','Alice','Realm'); b.phase='linked'; b.a=a.a; b.b=a.b; b.started=10; b.deadline=70; b.expires=a.expires
 local links={}; C.LinkSave(links,b,false); return b,links
end
assert(type(C.PlanPackets)=='function','linked plan transport missing')
local packets=assert(C.PlanPackets(a,wire,'200001',now,10))
local b,links=receiver()
for i,p in ipairs(packets) do
 assert(string.len(p)<=240 and C.PlanParse(p))
 local complete=C.PlanReceive(b,p,'Alice',links,now,11)
 assert(complete==(i==table.getn(packets)))
end
assert(b.planProposal and not b.planInput,'complete plan must wait for approval')
assert(not C.PlanReceive(b,packets[1],'Alice',links,now,11),'replay')
local db={presets={Existing={entries={{kind='legacy',charName='Oldmage'}}}},currentPreset='Existing',sortPresets={},currentSortPreset='Default'}
assert(not C.PlanImport(db,b,links,'Existing','copy',now,12),'silent overwrite')
assert(C.PlanImport(db,b,links,'Received','copy',now,12))
assert(db.currentPreset=='Existing' and db.presets.Existing.entries[1].charName=='Oldmage')
assert(db.presets.Received.entries[1].account=='Alice' and not next(db.presets.Received.denyRules))
assert(not C.PlanImport(db,b,links,'Again','copy',now,12),'approval replay')
local function received()
 local r,l=receiver(); for _,p in ipairs(packets) do C.PlanReceive(r,p,'Alice',l,now,11) end; return r,l
end
local function offer(entries)
 local r,l=receiver(); local text=assert(C.PlanEncode({entries=entries},'hire','Offer'))
 for _,p in ipairs(assert(C.PlanPackets(a,text,'200002',now,10))) do C.PlanReceive(r,p,'Alice',l,now,11) end
 assert(r.planProposal,'offer not received'); return r,l
end
local function occupied(entries)
 local n=0; for i=1,40 do if entries[i] and entries[i].kind~='empty' then n=n+1 end end; return n
end
b,links=received(); local existing=db.presets.Existing
local ok,result=C.PlanImport(db,b,links,'Existing','merge',now,12)
assert(ok and result.added==2 and result.moved==1,'slot conflict must relocate, not reject')
local merged=db.presets.Existing.entries
assert(merged[1].charName=='Oldmage' and merged[2].account=='Alice' and merged[3].charName=='Companion' and occupied(merged)==3)
assert(occupied(existing.entries)==1 and existing.entries[1].charName=='Oldmage','merge must stage a copy')
assert(db.currentPreset=='Existing' and not b.planProposal,'approved merge must consume its proposal')
b,links=received(); db.presets.Open={entries={{kind='empty'}},denyRules={{keep=true}},setupRules={}}
ok,result=C.PlanImport(db,b,links,'Open','merge',now,12)
assert(ok and result.added==2 and result.moved==0 and db.presets.Open.denyRules[1].keep)
db.presets.Busy={entries={[1]={kind='empty'},[2]={kind='legacy',charName='Keeper',denyList={'Smite'}},
 [4]={kind='normal',account='Guard',setup={pet='imp'}}},denyRules={{keep=true}},setupRules={{pet='imp'}}}
local busy=db.presets.Busy
b,links=offer({{kind='empty'},{kind='legacy',charName='Anna'},{kind='legacy',charName='Bert'},{kind='legacy',charName='Cara'},{kind='legacy',charName='Dana'}})
ok,result=C.PlanImport(db,b,links,'Busy','merge',now,12)
assert(ok and result.added==4 and result.moved==2,'added counts every written row; moved counts relocated rows')
merged=db.presets.Busy.entries
assert(merged[3].charName=='Bert' and merged[5].charName=='Dana','free original slots must be reserved before relocation')
assert(merged[1].charName=='Anna' and merged[6].charName=='Cara','conflicts take the lowest remaining free slots in incoming order')
assert(merged[2].charName=='Keeper' and merged[2].denyList[1]=='Smite' and merged[4].account=='Guard' and merged[4].setup.pet=='imp'
 and occupied(merged)==6,'occupied slot or its settings changed')
assert(db.presets.Busy.denyRules[1].keep and db.presets.Busy.setupRules[1].pet=='imp','plan settings changed')
assert(occupied(busy.entries)==2 and busy.entries[1].kind=='empty' and not busy.entries[3],'original plan object mutated')
local full={entries={},denyRules={},setupRules={}}; db.presets.Full=full
for i=1,39 do full.entries[i]={kind='legacy',charName='Keeper'} end; full.entries[40]={kind='empty'}
local incoming={{kind='legacy',charName='Anna'}}; for i=2,39 do incoming[i]={kind='empty'} end; incoming[40]={kind='legacy',charName='Dana'}
b,links=offer(incoming); local proposal=b.planProposal
ok,result=C.PlanImport(db,b,links,'Full','merge',now,12)
assert(not ok and result=='capacity','merge without enough free slots must fail with a reason')
assert(db.presets.Full==full and occupied(full.entries)==39 and full.entries[40].kind=='empty','capacity failure must be atomic')
assert(b.planProposal==proposal,'failed merge consumed the proposal')
full.entries[39]={kind='empty'}; ok,result=C.PlanImport(db,b,links,'Full','merge',now,12)
assert(ok and result.added==2 and result.moved==1 and not b.planProposal,'retained proposal must merge once a slot is free')
assert(db.presets.Full.entries[39].charName=='Anna' and db.presets.Full.entries[40].charName=='Dana')
assert(db.currentPreset=='Existing' and db.currentSortPreset=='Default','merge changed the current selection')
for _,bad in ipairs({'sender','target','realm','nonce','stale','unauthorized','duplicate','oversize','order'}) do
 b,links=receiver(); local p=packets[1]; local sender='Alice'; local wall=now
 if bad=='sender' then sender='Mallory'
 elseif bad=='target' then p=string.gsub(p,';Bob;',';Carol;')
 elseif bad=='realm' then p=string.gsub(p,';Realm;',';Elsewhere;')
 elseif bad=='nonce' then p=string.gsub(p,';100001;',';999999;')
 elseif bad=='stale' then wall=now+61
 elseif bad=='unauthorized' then links={}
 elseif bad=='oversize' then p=p..string.rep('x',241)
 elseif bad=='order' then p=packets[2]
 elseif bad=='duplicate' then C.PlanReceive(b,p,sender,links,wall,11) end
 assert(not C.PlanReceive(b,p,sender,links,wall,11),bad)
 assert(not b.planProposal,bad..' approved')
end
b,links=received(); C.PlanReject(b); assert(not C.PlanImport(db,b,links,'Rejected','copy',now,12))
b,links=received(); C.LinkForget(links,'Bob','Alice','Realm',false); assert(not C.PlanImport(db,b,links,'Revoked','copy',now,12))
b,links=received(); assert(not C.PlanImport(db,b,links,'Stale','copy',now+61,71))
C.PeerClear(b); assert(C.PeerArm(b,'333333',now+62,72)); assert(not next(b.planSeen),'new session must reset its bounded replay budget')
print("Shir's Raid Builder plan share tests: PASS")
