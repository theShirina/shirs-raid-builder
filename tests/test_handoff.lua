dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local p={entries={ [1]={kind='normal',account='Alice',class='mage',role='rdps',race='human',gender='female',tier='t2r',spec='frost'}, [6]={kind='normal',account='Bob',class='warlock',role='rdps',race='human',gender='male',tier='t2r',spec='default'},[11]={kind='legacy',charName='Legacy',class='priest',role='healer'} }}
assert(type(C.HandCreate)=='function','staged handoff core missing')
local h=assert(C.HandCreate(p,'Raid','Alice','FixtureRealm',{ 'Alice','Bob','Alice' },'1234567890123456',1800000000))
assert(h.step==1 and h.phase=='ready')
local wire=assert(C.HandEncode(h)); assert(C.HandDecode(wire).plan.entries[6].account=='Bob')
local alice={}; local bob={}; alice.active=h
assert(not C.HandComplete(h,'Alice'),'unexecuted completion accepted')
local q=assert(C.HandStepPlan(h,{denyRules={{class='mage',role='rdps',abilities={'Fireball'}}}},'Alice'))
assert(q.entries[1].account=='Alice' and not q.entries[6] and q.denyRules[1])
assert(not C.HandStepPlan(h,{},'Bob'),'foreign actor can execute')
h.phase='submitted'; assert(C.HandComplete(h,'Alice')); assert(h.step==2 and h.phase=='waiting')
local offer=assert(C.HandEncode(h)); local received=assert(C.HandDecode(offer))
assert(C.HandApprove(bob,received,'Alice','Bob','FixtureRealm',1800000001))
assert(bob.active.phase=='ready' and bob.active.source=='alice')
assert(not C.HandApprove(bob,received,'Alice','Bob','FixtureRealm',1800000001),'duplicate approval')
local copy=assert(C.HandRestore(bob.active,'Bob','FixtureRealm',1800000002)); assert(copy.phase=='ready')
copy.phase='running'; copy=assert(C.HandRestore(copy,'Bob','FixtureRealm',1800000002)); assert(copy.phase=='interrupted','reload resumed money actions')
bob.active.phase='submitted'; assert(C.HandComplete(bob.active,'Bob'))
assert(C.HandApprove(alice,C.HandDecode(C.HandEncode(bob.active)),'Bob','Alice','FixtureRealm',1800000003))
assert(alice.active.step==3 and alice.active.phase=='ready')
assert(not C.HandApprove(alice,received,'Alice','Alice','FixtureRealm',1800000003),'stale step')
assert(not C.HandApprove({},C.HandDecode(offer),'Carol','Bob','FixtureRealm',1800000003),'wrong sender')
assert(not C.HandApprove({},C.HandDecode(offer),'Alice','Bob','OtherRealm',1800000003),'wrong realm')
assert(not C.HandApprove({},C.HandDecode(offer),'Alice','Bob','FixtureRealm',1800086400),'expired workflow')
alice.active.phase='submitted'; assert(C.HandComplete(alice.active,'Alice')); assert(alice.active.phase=='done')
local s=C.PeerNew('Alice','Bob','FixtureRealm'); s.phase='linked'; s.a='100001'; s.b='100002'; s.expires=1800000060; s.started=100; s.deadline=160
local r=C.PeerNew('Bob','Alice','FixtureRealm'); r.phase='linked'; r.a=s.a; r.b=s.b; r.expires=s.expires; r.started=100; r.deadline=160
local links={}; C.LinkSave(links,r,false)
local packets=assert(C.HandPackets(s,offer,'900001',1800000000,100))
for _,packet in ipairs(packets) do assert(string.len(packet)<=240); C.HandReceive(r,packet,'Alice',links,1800000000,100) end
assert(r.handProposal and not r.planProposal,'bounded handoff transport failed')
for _,packet in ipairs(packets) do assert(not C.HandReceive(r,packet,'Alice',links,1800000000,100)) end
assert(not C.HandReceive(r,packets[1],'Carol',links,1800000000,100))
print("Shir's Raid Builder handoff core tests: PASS")
assert(not C.HandApprove({seen='broken'},C.HandDecode(offer),'Alice','Bob','FixtureRealm',1800000003),'malformed seen accepted')
assert(not C.HandApprove({seen={['1234567890123456']={expires=1800086400}}},C.HandDecode(offer),'Alice','Bob','FixtureRealm',1800000003),'malformed replay record accepted')
