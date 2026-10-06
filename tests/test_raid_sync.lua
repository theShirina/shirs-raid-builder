dofile("../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua")
local C=ShirsRaidBuilderCore
local checks=0
local function ok(v) checks=checks+1; assert(v,"raid check "..checks) end
local function session(you,peer)
 local s=C.PeerNew(you,peer,"Realm")
 s.phase="linked"; s.a="111111"; s.b="222222"; s.started=10; s.deadline=100; s.expires=2000
 s.raidWait={nonce="333333",started=10,entries={},count=0}
 return s
end
local ccp={locks={{name="Blackwing Lair",id=9,resetAt=110}},sched={{name="Molten Core",cycle=7,resetAt=150},{name="Zul Gurub",cycle=3,resetAt=160},{name="Expired",cycle=7,resetAt=5},{name="Bad",cycle=1.5,resetAt=160}}}
local snap=C.RaidSnapshot({{name="Molten Core",id=123,reset=200}},ccp,1000,10)
ok(snap.known and table.getn(snap.entries)==3)
ok(snap.entries[1].id==123 and snap.entries[1].readyAt==1200 and not snap.entries[1].scheduled)
ok(snap.entries[3].scheduled and snap.entries[3].cycle==3)
ok(not C.RaidSnapshot(nil,ccp,1000,10).known)
ok(table.getn(C.RaidSnapshot({{name="Expired",id=1,reset=0},{name="Huge",id=2,reset=1e100},{name="NaN",id=3,reset=0/0}},nil,1000,10).entries)==0)
local expired=C.RaidSnapshot({{name="Molten Core",id=1,reset=0}},ccp,1000,10)
for _,e in ipairs(expired.entries) do ok(e.name~="Molten Core") end
local tx=session("Alice","Bob")
local packets=C.RaidPackets(tx,"333333",snap)
ok(packets and table.getn(packets)==3)
for _,p in ipairs(packets) do ok(string.len(p)<=240 and C.RaidParse(p)) end
local rx=session("Bob","Alice")
local old={sentinel=true}; rx.remoteRaids=old
ok(not C.RaidReceive(rx,packets[1],"Mallory",1000,10))
ok(not C.RaidReceive(rx,string.gsub(packets[1],"111111","999999"),"Alice",1000,10))
ok(not C.RaidReceive(rx,string.gsub(packets[1],"333333","999999"),"Alice",1000,10))
ok(not C.RaidReceive(rx,packets[2],"Alice",1000,10) and rx.remoteRaids==old)
ok(not C.RaidReceive(rx,packets[2],"Alice",1000,10))
ok(not C.RaidReceive(rx,packets[1],"Alice",1000,10))
rx.licenseWait=nil
ok(C.RaidReceive(rx,packets[3],"Alice",1001,11))
ok(rx.remoteRaids.source=="alice" and rx.remoteRaids.character=="Alice" and rx.remoteRaids.realm=="Realm" and rx.remoteRaids.authoritative==false)
ok(not C.RaidReceive(rx,packets[3],"Alice",1001,11))
local copy=C.RaidSavedCopy(rx.remoteRaids)
ok(copy and copy.entries~=rx.remoteRaids.entries and copy.entries[1]~=rx.remoteRaids.entries[1])
copy.entries[1].readyAt=0; ok(not C.RaidSavedCopy(copy))
rx=session("Bob","Alice"); ok(not C.RaidReceive(rx,packets[1],"Alice",1030,40))
rx=session("Bob","Alice"); ok(not C.RaidReceive(rx,packets[1],"Alice",1000,55))
for _,known in ipairs({true,false}) do
 local p=C.RaidPackets(tx,"333333",{known=known,entries={},observed=1000})
 rx=session("Bob","Alice")
 ok(p and table.getn(p)==1 and C.RaidReceive(rx,p[1],"Alice",1000,10))
 ok(rx.remoteRaids.known==known and table.getn(rx.remoteRaids.entries)==0)
end
ok(not C.RaidParse(string.rep("x",241)))
ok(not C.RaidParse(string.gsub(packets[1],"Molten Core","Bad|Name")))
ok(not C.RaidParse(string.gsub(packets[1],"1200","999999999999999999999")))
local many={}; for i=1,33 do many[i]={name="Raid "..i,id=i,reset=100} end
ok(not C.RaidSnapshot(many,nil,1000,10).known)
local bad={known=true,observed=1000,entries={[2]={name="Raid",id=1,readyAt=1100,scheduled=false}}}
ok(not C.RaidPackets(tx,"333333",bad))
rx=session("Bob","Alice")
ok(not C.RaidReceive(rx,packets[1],"Alice",1000,10))
local conflict=string.gsub(packets[1],"1200","1201")
ok(not C.RaidReceive(rx,conflict,"Alice",1000,10) and rx.raidWait==nil)
print("PASS raid sync: "..checks.." checks (Lua ".._VERSION..")")
