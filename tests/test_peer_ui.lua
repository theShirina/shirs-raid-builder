-- Installed account-link UI safety contracts; SRBPOC1 input is never trusted.
local file=assert(io.open('test_individual_editor.lua','r')); local fixture=file:read('*a'); file:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local function client(name,peer,saved)
    local h=boot(saved,name); h.now=100; h.wall=1800000000; h.sent={}
    h.env.GetTime=function() return h.now end; h.env.time=function() return h.wall end
    h.env.SendChatMessage=function(text,route,language,target)
        assert(route=='WHISPER' and language==nil,'only handshake whispers allowed in this fixture')
        assert(h.C.LinkParse(text) or h.C.LicenseParse(text))
        table.insert(h.sent,{text=text,target=target})
    end
    h.C.OpenPeerPOC(); h.C.peerPanel.nameInput:SetText(peer)
    return h,h.C.peerPanel
end
local function tick(h)
    h.now=h.now+1; h.wall=h.wall+1; h:fire(h.C.peerDriver,'OnUpdate',1)
end
local function eventAt(h,event,text,sender)
    h.env.event=event; h.env.arg2=sender; h:fire(h.C.peerDriver,'OnEvent',text)
end
local function deliver(from,to)
    local packet=assert(table.remove(from.sent,1),'expected outgoing handshake')
    eventAt(to,'CHAT_MSG_WHISPER',packet.text,from.env.UnitName('player')); return packet.text
end
local function state(h,name) return h.C.peerSessions['FixtureRealm;'..string.lower(name)].state end
-- Every caption the real constructor placed directly on a frame, in creation order.
local function captions(h,parent)
    local all={}
    for _,w in ipairs(h.frames) do if w.kind=='FontString' and w.parent==parent then table.insert(all,w:GetText()) end end
    return table.concat(all,'\n')
end
local PROMPT_HELP='Unchecked: approval covers only this local character.\nAccept lets the peer hire and spend gold for its plan after Execute\non the initiating account. Licenses are peer claims, not proof.'
local PANEL_HELP='Licenses are peer claims, not ownership proof. Accepting a link\nallows plan-scoped hiring and gold spending after Execute on the\ninitiating account. Opening SRB does not sync; use Refresh\nSynchronization to retry. Both peers need this version.'
local PANEL_STATUS='Sidebar rows are view-only. Linked hires can spend gold after Execute\non the initiating account, only for that plan.'
local function noHiringDenial(text,where)
    assert(not string.find(text,'No account proof or hiring permission',1,true),where..' denies hiring permission')
    assert(not string.find(text,'remote hiring is unavailable',1,true),where..' says remote hiring is unavailable')
    assert(not string.find(text,'not proof of ownership. Read-only.',1,true),where..' calls the whole link read-only')
end
local a,af=client('Alice','Bob'); local b,bf=client('Bob','Alice')
a:click(af.pairButton)
assert(table.getn(a.sent)==0,'send must be deferred')
a.now=100.999; a:fire(a.C.peerDriver,'OnUpdate',0.999); assert(table.getn(a.sent)==0)
a.now=100; tick(a); local invitation=deliver(a,b); tick(b)
assert(b.C.peerPrompt:IsShown() and b.C.peerPrompt.raised and b.C.peerPrompt:GetFrameStrata()=='FULLSCREEN_DIALOG')
assert(state(b,'Alice').phase=='approval','incoming invitation auto-approved')
-- Before Accept, the visible prompt discloses plan-scoped hiring and gold spending.
local promptText=captions(b,b.C.peerPrompt)
assert(string.find(promptText,PROMPT_HELP,1,true),'approval prompt does not disclose hiring and gold spending before Accept')
noHiringDenial(promptText,'approval prompt')
assert(b.C.peerPrompt.acceptButton:IsVisible() and not b.C.peerPrompt.rememberCheck:GetChecked(),'disclosure must be visible beside an unchecked Accept')
b.C.peerPrompt.rememberCheck:SetChecked(1); b:click(b.C.peerPrompt.acceptButton)
tick(b); deliver(b,a); tick(a); deliver(a,b); tick(b); deliver(b,a)
assert(state(a,'Bob').phase=='linked' and state(b,'Alice').phase=='linked')
assert(a.C.LinkKnown(a.env.ShirsRaidBuilderDB.peerLinks,'Alice','Bob','FixtureRealm'))
assert(b.C.LinkKnown(b.env.ShirsRaidBuilderDB.peerLinks,'Other','Alice','FixtureRealm'),'remember-account approval')
local entries=a:preset().entries; local count=table.getn(entries)
eventAt(a,'CHAT_MSG_WHISPER','SRBPOC1;EXECUTE;Alice','Bob')
eventAt(a,'CHAT_MSG_WHISPER','SRBLINK2;EXECUTE;FixtureRealm;Bob;Alice;100001;100002;1800000060','Bob')
assert(a:preset().entries==entries and table.getn(entries)==count,'remote action mutated entries')
-- Local Cancel clears exactly the visible endpoint, and replay cannot resurrect it.
a:click(af.cancelButton); assert(state(a,'Bob').phase=='disabled')
eventAt(a,'CHAT_MSG_WHISPER',invitation,'Bob'); assert(state(a,'Bob').phase=='disabled')
for _,name in ipairs({'PLAYER_LEAVING_WORLD','PLAYER_ENTERING_WORLD','PLAYER_LOGOUT'}) do
    local h,f=client('Alice','Bob'); h:click(f.pairButton)
    eventAt(h,name); tick(h)
    assert(state(h,'Bob').phase=='disabled' and table.getn(h.sent)==0,'context left queued traffic: '..name)
end
-- A group change touches no link trust (whisper senders, saved approval, nonces): each hire
-- changes the roster on both clients, so it must never cancel a handshake or transfer.
for _,name in ipairs({'PARTY_MEMBERS_CHANGED','RAID_ROSTER_UPDATE'}) do
    local h,f=client('Alice','Bob'); h:click(f.pairButton)
    eventAt(h,name); tick(h)
    assert(state(h,'Bob').phase=='waiting' and table.getn(h.sent)==1,'roster change cancelled the link: '..name)
end
local h,f=client('Alice','Bob'); h:click(f.pairButton)
eventAt(h,'CHAT_MSG_SYSTEM','unrelated message'); assert(state(h,'Bob').phase=='waiting','unrelated system chat cancels addressed session')
eventAt(h,'CHAT_MSG_WHISPER_INFORM',h.C.peerPending,'Alice'); assert(state(h,'Bob').phase=='waiting','outgoing echo treated as receipt')
h.env.SendChatMessage=function() error('transport unavailable') end
tick(h); assert(state(h,'Bob').phase=='disabled' and not h.C.peerPending)
tick(h); assert(state(h,'Bob').phase=='disabled','automatic retry after failure')
h,f=client('Alice','Bob'); h:click(f.pairButton); h.now=161; h.wall=1800000061; tick(h)
assert(state(h,'Bob').phase=='disabled' and table.getn(h.sent)==0,'expired invitation sent')
h,f=client('Alice','Bob'); h:click(f.pairButton); h.C.sortFrame={busy=true}; tick(h)
assert(state(h,'Bob').phase=='disabled' and table.getn(h.sent)==0,'peer traffic overlapped sort')
h,f=client('Alice','Bob'); h:click(f.pairButton)
for i=1,32 do local name=debug.getupvalue(h.C.PeerContextOK,i); if name=='executing' then debug.setupvalue(h.C.PeerContextOK,i,true); break end end
tick(h); assert(state(h,'Bob').phase=='disabled' and table.getn(h.sent)==0,'peer traffic overlapped hires')
h,f=client('Alice','Bob'); h:click(f.pairButton); h.env.ShirsRaidBuilderMainFrame:Hide()
assert(not f:IsShown() and state(h,'Bob').phase=='disabled','main close must cancel unsent work')
-- Edits are selection, not authorization: another peer's pending consent survives.
h,f=client('Alice','Bob'); h:click(f.pairButton); local pending=h.C.peerPending
for _,bad in ipairs({'','Bob Alice','Alice',' Bob','Bob-Realm'}) do
    f.nameInput:SetText(bad); assert(not f.pairButton:IsEnabled(),'invalid visible endpoint enabled Pair')
    h.C.LinkPair(); assert(h.C.peerPending==pending and state(h,'Bob').phase=='waiting','invalid edit touched another peer')
end
f.nameInput:SetText('Carol'); h:click(f.pairButton)
assert(state(h,'Carol').phase=='waiting' and state(h,'Bob').phase=='waiting')
f.nameInput:SetText('Bob'); h:click(f.cancelButton)
assert(state(h,'Bob').phase=='disabled' and state(h,'Carol').phase=='waiting','Cancel crossed endpoint')
h,f=client('Alice','Bob'); h:click(f.pairButton)
h.env.ShirsRaidBuilderEscaper:Hide()
assert(not f:IsShown() and state(h,'Bob').phase=='disabled' and not h.C.peerPending,'Escape left the visible invitation queued')
-- The exact version-1 shape is only a draft; never turn old one-sided config into trust.
local legacy={version=1,confirmed=true,you='tester',peer='bob',realm='FixtureRealm',enabled=true,nonce='999999',proposal={total=40}}
h,f=client('Tester','Bob'); h.env.ShirsRaidBuilderDB.peerConfig=legacy
local reload=boot(h.env.ShirsRaidBuilderDB,'Tester'); reload.C.OpenPeerPOC()
assert(reload.C.peerPanel.nameInput:GetText()=='bob' and not reload.C.peerState)
assert(not reload.env.ShirsRaidBuilderDB.peerConfig and not next(reload.env.ShirsRaidBuilderDB.peerLinks),'old POC migrated as mutual approval')
for _,bad in ipairs({false,'invalid',{version=1,confirmed=false,you='tester',peer='Bob',realm='FixtureRealm'},
    {version=1,confirmed=true,you='someoneelse',peer='Bob',realm='FixtureRealm'},
    {version=2,confirmed=true,you='tester',peer='Bob',realm='FixtureRealm'}}) do
    h,f=client('Tester','Bob'); h.env.ShirsRaidBuilderDB.peerConfig=bad; reload=boot(h.env.ShirsRaidBuilderDB,'Tester')
    assert(not reload.C.peerState and not reload.C.peerDraft and not reload.env.ShirsRaidBuilderDB.peerConfig)
end
local foundTitle=false
for _,w in ipairs(h.frames) do
    if w.GetText then
        local text=w:GetText(); assert(not string.find(text,'Peer POC',1,true) and not string.find(text,'SRB Peer',1,true))
        if text=='Link another account' then foundTitle=true end
    end
end
assert(foundTitle)
-- Link panel help and status disclose plan-scoped hiring; the license view stays read-only.
h,f=client('Alice','Bob'); h:click(f.licenseButton)
local panelText=captions(h,f)
assert(string.find(panelText,PANEL_HELP,1,true),'link panel help does not disclose plan-scoped hiring')
assert(string.find(f.status:GetText(),PANEL_STATUS,1,true),'link panel status does not disclose linked hires')
noHiringDenial(panelText,'link panel')
local viewText=captions(h,h.C.licenseView)
assert(string.find(viewText,'Advisory peer licenses (read-only)',1,true),'license view lost its read-only title')
assert(string.find(h.C.licenseView.status:GetText(),PANEL_STATUS,1,true),'license view status differs from the panel')
noHiringDenial(viewText,'license view')
-- Both remember settings keep their existing scope after the disclosed Accept.
for _,remember in ipairs({false,true}) do
    local c,cf=client('Carol','Dave'); local d,df=client('Dave','Carol')
    c:click(cf.pairButton); tick(c); deliver(c,d); tick(d)
    assert(d.C.peerPrompt:IsShown() and string.find(captions(d,d.C.peerPrompt),PROMPT_HELP,1,true),'disclosure missing before Accept')
    if remember then d.C.peerPrompt.rememberCheck:SetChecked(1) end
    d:click(d.C.peerPrompt.acceptButton)
    tick(d); deliver(d,c); tick(c); deliver(c,d); tick(d); deliver(d,c)
    assert(state(c,'Dave').phase=='linked' and state(d,'Carol').phase=='linked','disclosed Accept did not link')
    local links=d.env.ShirsRaidBuilderDB.peerLinks
    assert(d.C.LinkKnown(links,'Dave','Carol','FixtureRealm'),'approval lost this local character')
    assert((d.C.LinkKnown(links,'Other','Carol','FixtureRealm') and true or false)==remember,'remember checkbox changed approval scope')
    d.C.PeerRefresh()
    local scope=remember and 'Saved approval: all local characters' or 'Saved approval: this local character'
    assert(string.find(df.status:GetText(),scope,1,true),'visible approval scope changed')
    assert(string.find(df.status:GetText(),PANEL_STATUS,1,true),'linked status does not disclose linked hires')
    noHiringDenial(df.status:GetText(),'linked status')
end
print("Shir's Raid Builder peer UI tests: PASS")
