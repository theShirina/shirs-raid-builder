dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local now=1800000000
local rows=C.AccountCollect({
    {name='Druid',level=60,dungeonLicense='t3d',raidLicense='t4r'},
    {name='Warrior',level=60,dungeonLicense='t2d',raidLicense='t2r'},
    {name='Young',level=59,dungeonLicense='t5d',raidLicense='t5r'},
    {name='Unknown',raidLicense='t5r'}, {name='Over',level=61}},now)
assert(table.getn(rows)==2 and rows[1].name=='Druid' and rows[2].name=='Warrior','only exact known level 60')
assert(rows[1].level==60 and rows[1].dungeonLicense=='t3d')
local raids={known=true,observedAt=now-100,instances={{name='Molten Core',readyAt=now+100},{name='Blackwing Lair',readyAt=now+200},{name='Naxxramas',readyAt=now+300,scheduled=true}}}
C.AccountSetRaids(rows[1],raids,now)
assert(C.AccountRaidLabels(rows[1],now)=='MC BWL')
assert(rows[1].raidObserved==now-100,'cache observation must not become fresh on send')
assert(C.AccountRaidLabels(rows[2],now)=='','druid saves leaked to warrior')
local merged=C.AccountMerge(rows,C.AccountCollect({{name='Warrior',level=60,raidLicense='t3r'}},now+1))
assert(table.getn(merged)==2 and C.AccountRaidLabels(merged[1],now)=='MC BWL','partial refresh dropped druid/saves')
assert(merged[2].raidLicense=='t3r')
local s=C.PeerNew('Warrior','Viewer','Realm'); s.phase='linked'; s.a='100001'; s.b='100002'; s.started=10; s.deadline=70; s.expires=now+60
local target=C.PeerNew('Viewer','Warrior','Realm'); target.phase='linked'; target.a=s.a; target.b=s.b; target.started=10; target.deadline=70; target.expires=s.expires
local function receive(packets)
    C.LicenseRequest(target,'200001',10)
    local result=false
    for _,packet in ipairs(packets) do
        assert(string.len(packet)<=240 and C.AccountParse(packet))
        result=C.AccountReceive(target,packet,'Warrior',now,11)
    end
    return result
end
local packets=assert(C.AccountPackets(s,'200001','1234567890123456',merged,now+1))
assert(not receive(packets),'future batch must fail')
packets=assert(C.AccountPackets(s,'200001','1234567890123456',rows,now))
assert(receive(packets))
assert(target.remoteLicense.accountId=='1234567890123456')
assert(C.AccountRaidLabels(target.remoteLicense.entries[1],now)=='MC BWL')
assert(not C.AccountReceive(target,packets[1],'Warrior',now,11),'replay completed request')
target.licenseWait=nil; C.LicenseRequest(target,'200001',10)
assert(not C.AccountReceive(target,packets[1],'Mallory',now,11))
for i=1,table.getn(packets)-1 do assert(not C.AccountReceive(target,packets[i],'Warrior',now,11),'partial commit') end
assert(not target.remoteLicense)
local links={}; C.LinkSave(links,target,true)
assert(C.AccountReceive(target,packets[table.getn(packets)],'Warrior',now,11))
local copy=assert(C.AccountSavedCopy(target.remoteLicense,'Viewer','Realm',links))
assert(copy.entries[1].level==60 and copy.authoritative==false)
copy.entries[1].level=59; assert(not C.AccountSavedCopy(copy,'Viewer','Realm',links),'persisted lower level accepted')
assert(not C.AccountPackets(s,'200001','not-an-id',rows,now))
assert(not C.AccountParse(packets[1]..';extra'))
-- "unknown" carries no information: a newer row without licence data keeps the known licence,
-- while a newer real value, including "none", still replaces it.
local known=C.AccountCollect({{name='Druid',level=60,dungeonLicense='t3d',raidLicense='t4r'}},now)
local blank=C.AccountCollect({{name='Druid',level=60}},now+5)
local kept=C.AccountMerge(known,blank)
assert(kept[1].raidLicense=='t4r' and kept[1].dungeonLicense=='t3d' and kept[1].observed==now+5,'unknown licence hid a known one')
kept=C.AccountMerge(blank,known)
assert(kept[1].raidLicense=='t4r','older unknown row beat a known licence')
local cleared=C.AccountMerge(known,C.AccountCollect({{name='Druid',level=60,dungeonLicense='none',raidLicense='none'}},now+6))
assert(cleared[1].raidLicense=='none' and cleared[1].dungeonLicense=='none','newer real licence ignored')
-- A row carries its character's faction when the account knows it, so a linked account can
-- offer only that faction's races. A row without one, as older builds send, still parses.
local sided=C.AccountCollect({{name='Druid',level=60,dungeonLicense='t3d',raidLicense='t4r',faction='Alliance'},
    {name='Shaman',level=60,dungeonLicense='none',raidLicense='t5r',faction='Horde'},
    {name='Warrior',level=60,dungeonLicense='t2d',raidLicense='t2r'}},now)
assert(sided[1].faction=='Alliance' and sided[2].faction=='Horde' and sided[3].faction==nil,'faction not collected')
assert(C.AccountCollect({{name='Odd',level=60,faction='Neutral'}},now)[1].faction==nil,'a faction other than Alliance or Horde was kept')
packets=assert(C.AccountPackets(s,'200001','1234567890123456',sided,now))
target.licenseWait=nil
assert(receive(packets),'rows with factions were refused')
local got={}; for _,r in ipairs(target.remoteLicense.entries) do got[r.name]=r.faction or '-' end
assert(got.Druid=='Alliance' and got.Shaman=='Horde' and got.Warrior=='-','factions lost on the wire: '..tostring(got.Druid)..' '..tostring(got.Shaman)..' '..tostring(got.Warrior))
copy=assert(C.AccountSavedCopy(target.remoteLicense,'Viewer','Realm',links))
assert(copy.entries[1].faction=='Alliance' and copy.entries[2].faction=='Horde' and copy.entries[3].faction==nil,'saved copy changed factions')
local rowPacket
for _,p in ipairs(packets) do if string.find(p,';ROW;',1,true) and string.find(p,';Druid;',1,true) then rowPacket=p end end
assert(rowPacket and string.sub(rowPacket,-2)==';A','row does not end with its faction: '..tostring(rowPacket))
assert(not C.AccountParse(string.sub(rowPacket,1,-2)..'X'),'a bad faction token parsed')
local older=C.AccountParse(string.sub(rowPacket,1,-3))
assert(older and older.row.name=='Druid' and older.row.faction==nil,'a row without a faction was refused')
-- A newer observation without a faction keeps the known one.
local refreshed=C.AccountMerge(sided,C.AccountCollect({{name='Druid',level=60,dungeonLicense='t3d',raidLicense='t5r'}},now+5))
assert(refreshed[1].faction=='Alliance' and refreshed[1].raidLicense=='t5r','a newer row without a faction dropped the known one')
print("Shir's Raid Builder account sync tests: PASS")
