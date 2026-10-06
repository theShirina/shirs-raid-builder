-- Installed link/claim protocol, not the retired proposal POC. Exact Lua 5.0.3.
dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local function handshake()
    local a=assert(C.PeerNew('Alice','Bob','Fixture Realm'))
    local invitation=assert(C.LinkInvite(a,'100001',1000,10))
    local b=assert(C.LinkIncoming(invitation,'Alice','Bob','Fixture Realm','100002',1001,11))
    local accept=assert(C.LinkAccept(b,1001,11))
    local confirm=assert(C.LinkReceive(a,accept,'Bob',1002,12))
    local ready=assert(C.LinkReceive(b,confirm,'Alice',1003,13))
    assert(C.LinkReceive(a,ready,'Bob',1004,14)==true)
    assert(a.phase=='linked' and b.phase=='linked')
    assert(not C.LinkReceive(a,ready,'Bob',1004,14),'duplicate ready')
    return a,b,invitation,accept,confirm,ready
end
local a,b,invitation,accept,confirm=handshake()
for _,bad in ipairs({invitation..';extra',string.rep('x',241),string.gsub(invitation,'SRBLINK2','SRBLINK1'),
    string.gsub(invitation,'Fixture Realm','Other Realm'),string.gsub(invitation,';Bob;',';Carol;'),
    string.gsub(invitation,';1060',';999'),string.gsub(invitation,';1060',';9999999999'),
    string.gsub(invitation,';INVITE;',';EXECUTE;'),string.gsub(invitation,';100001;',';1;'),
    string.gsub(invitation,';INVITE;',';DATA;'),invitation..'\n'}) do
    assert(not C.LinkIncoming(bad,'Alice','Bob','Fixture Realm','100003',1001,11),'malformed/stale: '..bad)
end
for _,sender in ipairs({'Mallory','Alice-Otherrealm',' Alice',''}) do
    assert(not C.LinkIncoming(invitation,sender,'Bob','Fixture Realm','100003',1001,11))
end
assert(not C.PeerNew('Alice','Alice','Fixture Realm'))
assert(not C.PeerNew('Alice','Bob-Realm','Fixture Realm'))
assert(not C.PeerNew('Alice','Bob','Bad;Realm'))
assert(not C.PeerNew('Alice','Bob',' Realm'))
local stale=assert(C.LinkIncoming(invitation,'Alice','Bob','Fixture Realm','100003',1001,11))
assert(C.LinkAccept(stale,1001,11))
assert(not C.LinkReceive(stale,confirm,'Alice',1003,13),'old responder nonce after reload')
C.PeerClear(stale,'cancelled')
assert(not C.LinkReceive(stale,confirm,'Alice',1003,13) and not stale.a)
local expired=C.PeerNew('Alice','Bob','Fixture Realm'); C.LinkInvite(expired,'100005',1000,10)
assert(not C.PeerAlive(expired,1060,70) and expired.phase=='disabled')
expired=C.PeerNew('Alice','Bob','Fixture Realm'); C.LinkInvite(expired,'100005',1000,10)
assert(not C.PeerAlive(expired,1001,9),'uptime wrap')
assert(not C.LinkAccept(expired,1001,11) and not C.LicenseRequest(expired,'100008',11))
local rejected=C.LinkIncoming(invitation,'Alice','Bob','Fixture Realm','100009',1001,11)
assert(C.LinkReject(rejected,1001,11) and rejected.phase=='disabled')
local links={}; assert(C.LinkSave(links,a,true)); assert(C.LinkKnown(links,'Alt','Bob','Fixture Realm'))
C.LinkForget(links,'Alt','Bob','Fixture Realm',false)
assert(not C.LinkKnown(links,'Alt','Bob','Fixture Realm'))
assert(C.LinkKnown(links,'Alice','Bob','Fixture Realm'))
assert(not C.LinkKnown(links,'Alice','Bob','Other Realm'))
local request=assert(C.LicenseRequest(a,'200001',15)); assert(C.LicenseParse(request))
local packets=C.LicenseSnapshot(b,'200001',{{name='Bob',dungeonLicense='t2d',raidLicense='t3r'},
    {name='Alt',dungeonLicense='newtoken',raidLicense='t1r'}},1005)
assert(table.getn(packets)==2,'unknown license must not drop identity')
assert(not C.LicenseReceive(a,packets[1],'Mallory',1006,16))
assert(not C.LicenseReceive(a,string.gsub(packets[1],';200001;',';200002;'),'Bob',1006,16))
assert(not C.LicenseReceive(a,packets[1],'Bob',1006,16))
assert(not C.LicenseReceive(a,packets[1],'Bob',1006,16),'duplicate row')
assert(C.LicenseReceive(a,packets[2],'Bob',1006,16))
assert(not a.licenseWait and a.raidWait and a.raidWait.nonce=='200001','raid wait must survive license completion')
assert(a.remoteLicense.entries[1].name=='Alt' and a.remoteLicense.entries[1].dungeonLicense=='unknown')
local copy=assert(C.LicenseSavedCopy(a.remoteLicense,'Alice','Fixture Realm',links))
assert(copy.authoritative==false and copy.entries[2].raidLicense=='t3r')
assert(not C.LicenseSavedCopy(copy,'Alt','Fixture Realm',links),'revoked local link restores data')
copy.entries[1].command='.z addinvite Bob'; local clean=C.LicenseSavedCopy(copy,'Alice','Fixture Realm',links)
assert(clean and not clean.entries[1].command,'persisted action leaked through sanitizer')
copy.authoritative=true; assert(not C.LicenseSavedCopy(copy,'Alice','Fixture Realm',links))
assert(not C.LicenseSnapshot(b,'200001',{{name='Bad;Name',dungeonLicense='t1d',raidLicense='t1r'}},1005))
assert(not C.LicenseSnapshot(b,'200001',{{name='Alt',dungeonLicense='t1d',raidLicense='t1r'},{name='ALT',dungeonLicense='t2d',raidLicense='t1r'}},1005))
assert(not C.PeerReview and not C.PeerOffer and not C.PeerStart,'retired proposal/action protocol returned')
print("Shir's Raid Builder peer tests: PASS")
