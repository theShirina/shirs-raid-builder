local file=assert(io.open('test_individual_editor.lua','r')); local fixture=file:read('*a'); file:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local function client(name)
 local h=boot(nil,name); h.now=100; h.wall=1800000000; h.sent={}
 h.env.GetTime=function() return h.now end; h.env.time=function() return h.wall end
 h.env.SendChatMessage=function(text,route,language,target)
  assert(route=='WHISPER' and h.C.PlanParse(text),'plan sent a non-plan command')
  table.insert(h.sent,{text=text,target=target})
 end
 h.C.PeerOnBuilderOpen(); h.C.peerAutoAttempted=nil
 return h
end
local function link(h,peer)
 local s=h.C.PeerNew(h.env.UnitName('player'),peer,'FixtureRealm')
 s.phase='linked'; s.a='100001'; s.b='100002'; s.started=100; s.deadline=160; s.expires=h.wall+60
 h.C.SyncSelect(s,true); h.C.peerState=s; h.C.SyncStore(); h.C.LinkSave(h.env.ShirsRaidBuilderDB.peerLinks,s,false)
 return s
end
local a=client('Alice'); local b=client('Bob'); local c=client('Carol')
link(a,'Bob'); link(a,'Carol'); local bs=link(b,'Alice'); link(c,'Alice')
a:preset().entries[1]={kind='legacy',charName='Companion',class='mage',role='rdps',denyList={'Fireball'}}
assert(type(a.C.OpenPlanShare)=='function','visible plan share adapter missing')
-- Share Current Plan lives on the main frame beside Import, not in Link Account.
local main=a.env.ShirsRaidBuilderMainFrame
local import=a:button(main,'Import'); local share=a:button(main,'Share Current Plan')
assert(main.shareButton==share,'main frame share button missing')
assert(share.point[1]=='TOPLEFT' and share.point[5]==import.point[5],'share must sit on the Import row')
local sx,ix=share.point[4],import.point[4]
assert(sx+share:GetWidth()<=ix or sx>=ix+import:GetWidth(),'share overlaps Import')
assert(math.min(math.abs(ix-(sx+share:GetWidth())),math.abs(sx-(ix+import:GetWidth())))<=12,'share must be beside Import')
a.C.OpenPeerPOC(); assert(not a.C.peerPanel.shareButton,'share must leave the Link Account panel'); a.C.peerPanel:Hide()
a:click(share)
local f=a.C.planShareFrame
assert(f:IsShown() and table.getn(f.recipients)==2 and table.getn(a.sent)==0)
-- Receivers keep authenticated sessions with main and Link Account frames closed.
for _,h in ipairs({b,c}) do
 h.env.ShirsRaidBuilderMainFrame:Hide(); assert(not h.C.peerPanel or not h.C.peerPanel:IsShown())
end
a:click(f.recipientButtons[1]); a:click(f.recipientButtons[2]); a:click(f.sendButton)
assert(table.getn(a.sent)==0,'send not paced')
local function deliver(to,text)
 to.env.event='CHAT_MSG_WHISPER'; to.env.arg2='Alice'; to:fire(to.C.peerDriver,'OnEvent',text)
end
for i=1,120 do
 a.now=100+i*0.25; a.wall=1800000000+math.floor(i*0.25); a:fire(a.C.peerDriver,'OnUpdate',0.25)
 while table.getn(a.sent)>0 do local p=table.remove(a.sent,1); if p.target=='bob' then deliver(b,p.text) else assert(p.target=='carol'); deliver(c,p.text) end end
end
assert(bs.planProposal,'receiver did not receive complete plan')
b:fire(b.C.peerDriver,'OnUpdate',0.25); local prompt=b.C.planReceiveFrame
assert(prompt and prompt:IsShown(),'approval prompt must appear while receiver main frame is closed')
assert(not b.env.ShirsRaidBuilderMainFrame:IsShown(),'receipt must not open the builder')
assert(prompt.copyButton and prompt.mergeButton and prompt.rejectButton)
assert(not b.env.ShirsRaidBuilderDB.presets.Received,'receipt silently imported')
prompt.destination:SetText('Default'); b:click(prompt.copyButton); assert(prompt:IsShown(),'collision dismissed')
prompt.destination:SetText('Received'); b:click(prompt.copyButton)
assert(not prompt:IsShown() and b.env.ShirsRaidBuilderDB.currentPreset=='Default')
assert(b.env.ShirsRaidBuilderDB.presets.Received.entries[1].charName=='Companion')
assert(not b.env.ShirsRaidBuilderDB.presets.Received.entries[1].denyList)
assert(table.getn(b.sent)==0 and table.getn(c.sent)==0,'receive or approval sent commands')
c:fire(c.C.peerDriver,'OnUpdate',0.25); c:click(c.C.planReceiveFrame.rejectButton)
assert(not c.env.ShirsRaidBuilderDB.presets.Received)
for _,h in ipairs({b,c}) do
 assert(not h.env.ShirsRaidBuilderMainFrame:IsShown() and (not h.C.peerPanel or not h.C.peerPanel:IsShown()),'approval opened other frames')
 assert(h.env.ShirsRaidBuilderDB.currentPreset=='Default','approval changed the selected plan')
end
assert(string.find(f.message:GetText(),'Submitted',1,true),'sender needs a submission-complete status, not a receipt claim')
-- Closing the sender window before dispatch cancels only its queued plan.
a.C.OpenPlanShare(); f=a.C.planShareFrame; a:click(f.recipientButtons[1]); a:click(f.sendButton)
a:click(f.cancelButton)
for _,session in pairs(a.C.peerSessions) do assert(not session.state.planOut and not a.C.PlanParse(session.pending)) end
assert(table.getn(a.sent)==0)
-- A received plan cannot survive local cancellation, revocation or expiry.
local function proposal(h)
 local s=link(h,'Alice'); local sender=h.C.PeerNew('Alice',h.env.UnitName('player'),'FixtureRealm')
 sender.phase='linked'; sender.a=s.a; sender.b=s.b; sender.started=100; sender.deadline=160; sender.expires=h.wall+60
 local wire=assert(h.C.PlanEncode({entries={{kind='legacy',charName='Companion'}}},'hire','Offer'))
 h.env.ShirsRaidBuilderMainFrame:Hide()
 for _,p in ipairs(assert(h.C.PlanPackets(sender,wire,'999999',h.wall,100))) do deliver(h,p) end
 h:fire(h.C.peerDriver,'OnUpdate',0.25); return s
end
for _,reason in ipairs({'close','revoke','expiry','busy','realm'}) do
 local h=client('Bob'); local s=proposal(h); local ui=h.C.planReceiveFrame; assert(ui:IsShown())
 ui.destination:SetText('ShouldNotImport')
 if reason=='close' then ui:Hide() -- closing the prompt itself rejects; the main frame is irrelevant
 elseif reason=='revoke' then h.C.LinkForget(h.env.ShirsRaidBuilderDB.peerLinks,'Bob','Alice','FixtureRealm',false)
 elseif reason=='expiry' then h.now=161; h.wall=h.wall+61
 elseif reason=='busy' then h.C.sortFrame={busy=true}
 elseif reason=='realm' then h.env.GetRealmName=function() return 'OtherRealm' end end
 h:fire(ui.copyButton,'OnClick') -- also exercise stale handlers after close
 assert(not h.env.ShirsRaidBuilderDB.presets.ShouldNotImport,reason)
end
-- Clicking the main Share button refreshes only a stale saved-approved recipient,
-- through the existing SRBLINK2 handshake, and never sends the plan by itself.
do
 local ra=client('Alice'); local rb=client('Bob')
 local wire={}; local clock={now=100,wall=1800000000}
 -- Lua 5.0 reuses the generic-for variable, so bind each client in its own function scope.
 local function capture(client)
  local from=client.env.UnitName('player')
  client.env.SendChatMessage=function(text,route,language,target)
   assert(route=='WHISPER','stale refresh sent a non-whisper: '..tostring(route))
   local kind=client.C.LinkParse(text) and client.C.LinkParse(text).kind or (client.C.PlanParse(text) and 'PLAN')
   assert(kind,'stale refresh sent an unknown command')
   table.insert(wire,{from=from,to=target,kind=kind,text=text})
   table.insert(client.sent,{text=text,target=target,kind=kind})
  end
 end
 capture(ra); capture(rb)
 link(ra,'Bob'); link(rb,'Alice')
 ra:preset().entries[1]={kind='legacy',charName='Companion',class='mage',role='rdps'}
 local function count(kind) local n=0; for _,w in ipairs(wire) do if w.kind==kind then n=n+1 end end; return n end
 local function pump(steps)
  for i=1,steps do
   clock.now=clock.now+0.25; clock.wall=1800000000+math.floor((clock.now-100))
   for _,h in ipairs({ra,rb}) do h.now=clock.now; h.wall=clock.wall; h:fire(h.C.peerDriver,'OnUpdate',0.25) end
   for _,pair in ipairs({{ra,rb},{rb,ra}}) do
    local from,to=pair[1],pair[2]
    while table.getn(from.sent)>0 do
     local p=table.remove(from.sent,1)
     to.env.event='CHAT_MSG_WHISPER'; to.env.arg2=from.env.UnitName('player'); to:fire(to.C.peerDriver,'OnEvent',p.text)
    end
   end
  end
 end
 -- The saved approval is durable, but the live session has expired on both sides.
 clock.now=200; clock.wall=1800000100
 for _,h in ipairs({ra,rb}) do h.now=clock.now; h.wall=clock.wall end
 local key='FixtureRealm;bob'
 assert(ra.C.LinkKnown(ra.env.ShirsRaidBuilderDB.peerLinks,'Alice','Bob','FixtureRealm'),'saved approval missing')
 rb.env.ShirsRaidBuilderMainFrame:Hide()
 ra:click(ra:button(ra.env.ShirsRaidBuilderMainFrame,'Share Current Plan'))
 local f=ra.C.planShareFrame
 assert(f:IsShown() and table.getn(f.recipients)==1,'share popup did not open for the stale recipient')
 local opening=f.message:GetText()
 ra:click(ra:button(ra.env.ShirsRaidBuilderMainFrame,'Share Current Plan')) -- duplicate click before dispatch
 assert(table.getn(ra.sent)==0,'refresh bypassed handshake pacing')
 pump(8)
 assert(count('INVITE')==1,'stale click did not queue exactly one SRBLINK2 INVITE, saw '..count('INVITE'))
 ra:click(ra:button(ra.env.ShirsRaidBuilderMainFrame,'Share Current Plan')) -- duplicate click mid-handshake
 pump(40)
 assert(string.find(opening,'Refreshing',1,true),'popup must show Refreshing after the click, saw: '..tostring(opening))
 assert(count('INVITE')==1,'duplicate main Share click restarted the handshake')
 assert(count('ACCEPT')==1 and count('CONFIRM')==1 and count('READY')==1,'handshake did not complete through ACCEPT/CONFIRM/READY')
 local s=ra.C.peerSessions[key].state
 assert(s.phase=='linked' and ra.C.PlanAuthorized(s,ra.env.ShirsRaidBuilderDB.peerLinks,ra.wall,ra.now),'sender session not re-authenticated')
 assert(count('PLAN')==0,'refresh sent the plan without an explicit Send')
 assert(string.find(f.message:GetText(),'Refreshed',1,true) or string.find(f.message:GetText(),'ready',1,true),'popup must report refresh success, saw: '..tostring(f.message:GetText()))
 -- Only the user's explicit Send transmits the plan, and the receiver still chooses copy or merge.
 local bs2=rb.C.peerSessions['FixtureRealm;alice'].state
 ra:click(f.recipientButtons[1]); ra:click(f.sendButton); pump(120)
 assert(count('PLAN')>0 and bs2.planProposal,'explicit Send after refresh did not deliver the plan')
 rb:fire(rb.C.peerDriver,'OnUpdate',0.25)
 local prompt=rb.C.planReceiveFrame; assert(prompt and prompt:IsShown(),'receiver approval prompt missing')
 assert(not rb.env.ShirsRaidBuilderDB.presets.Refreshed,'plan imported before approval')
 prompt.destination:SetText('Refreshed'); rb:click(prompt.copyButton)
 assert(rb.env.ShirsRaidBuilderDB.presets.Refreshed.entries[1].charName=='Companion','receiver copy failed')
 -- A healthy session is never refreshed by another Share click.
 local invites=count('INVITE')
 ra:click(ra:button(ra.env.ShirsRaidBuilderMainFrame,'Share Current Plan')); pump(20)
 assert(count('INVITE')==invites,'healthy recipient was refreshed')
end
-- Negative-boundary coverage for the Share refresh (production handlers only).
-- Rig: named clients whose whispers cross a fake wire that only records and delivers.
local function wireup(net,h)
 local from=h.env.UnitName('player')
 h.env.SendChatMessage=function(text,route,language,target)
  if net.broken[from] then error('transport down') end
  assert(route=='WHISPER','non-whisper sent: '..tostring(route))
  local link=h.C.LinkParse(text)
  local kind=link and link.kind or (h.C.PlanParse(text) and 'PLAN')
  assert(kind,'unknown command sent')
  table.insert(net.wire,{from=from,to=target,kind=kind})
  table.insert(h.sent,{text=text,target=target})
 end
end
local function rig(names)
 local net={wire={},list={},byname={},cut={},broken={},clock={now=200,wall=1800000100}}
 for _,name in ipairs(names) do
  local h=client(name); wireup(net,h); table.insert(net.list,h); net.byname[string.lower(name)]=h
 end
 return net
end
local function age(net) for _,h in ipairs(net.list) do h.now=net.clock.now; h.wall=net.clock.wall end end
local function pump(net,steps)
 for i=1,steps do
  net.clock.now=net.clock.now+0.25; net.clock.wall=1800000000+math.floor(net.clock.now-100)
  for _,h in ipairs(net.list) do h.now=net.clock.now; h.wall=net.clock.wall; h:fire(h.C.peerDriver,'OnUpdate',0.25) end
  for _,h in ipairs(net.list) do
   while table.getn(h.sent)>0 do
    local p=table.remove(h.sent,1); local to=net.byname[p.target]
    if to and not net.cut[p.target] then
     to.env.event='CHAT_MSG_WHISPER'; to.env.arg2=h.env.UnitName('player'); to:fire(to.C.peerDriver,'OnEvent',p.text)
    end
   end
  end
 end
end
local function count(net,kind,to)
 local n=0
 for _,w in ipairs(net.wire) do if w.kind==kind and (not to or w.to==to) then n=n+1 end end
 return n
end
local function shareClick(h) h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Share Current Plan')) end
local function sessionOf(h,peer) return h.C.peerSessions['FixtureRealm;'..string.lower(peer)] end
local function withPlan(h) h:preset().entries[1]={kind='legacy',charName='Companion',class='mage',role='rdps'} end
-- Both sides hold the durable approval and an expired live session.
local function staleLink(net,sender,peer)
 link(sender,peer.env.UnitName('player')); link(peer,sender.env.UnitName('player'))
 peer.env.ShirsRaidBuilderMainFrame:Hide()
end
-- A live session the two sides still agree on, valid well past the test horizon.
local function renew(net,x,y)
 for _,pair in ipairs({{x,y},{y,x}}) do
  local s=sessionOf(pair[1],pair[2].env.UnitName('player')).state
  s.started=net.clock.now; s.deadline=net.clock.now+400; s.expires=net.clock.wall+400
 end
end
local function failed(f) return string.find(f.message:GetText(),'Refresh failed',1,true) end

-- Boundary: a saved approval with no runtime session at all still starts the handshake.
do
 local net=rig({'Alice','Bob'}); local ra,rb=net.list[1],net.list[2]
 local s=ra.C.PeerNew('Alice','Bob','FixtureRealm'); s.phase='linked'
 assert(ra.C.LinkSave(ra.env.ShirsRaidBuilderDB.peerLinks,s,false))
 assert(not (ra.C.peerSessions and sessionOf(ra,'Bob')),'fixture must start without a runtime session')
 link(rb,'Alice'); rb.env.ShirsRaidBuilderMainFrame:Hide(); age(net); withPlan(ra)
 shareClick(ra)
 local f=ra.C.planShareFrame
 assert(f:IsShown() and table.getn(f.recipients)==1,'missing-session recipient not listed')
 assert(sessionOf(ra,'Bob'),'refresh did not create the session')
 pump(net,8)
 assert(count(net,'INVITE','bob')==1,'missing session did not queue one INVITE, saw '..count(net,'INVITE','bob'))
 pump(net,60)
 assert(ra.C.PlanAuthorized(sessionOf(ra,'Bob').state,ra.env.ShirsRaidBuilderDB.peerLinks,ra.wall,ra.now),'missing-session refresh did not authenticate')
 assert(count(net,'PLAN')==0,'refresh sent a plan')
end

-- Boundary: timeout leaves no plan and no authenticated session.
do
 local net=rig({'Alice','Bob'}); local ra,rb=net.list[1],net.list[2]
 staleLink(net,ra,rb); age(net); withPlan(ra); net.cut['bob']=true
 shareClick(ra); local f=ra.C.planShareFrame
 pump(net,300)
 assert(count(net,'INVITE','bob')==1,'timeout run must still have invited once')
 assert(failed(f),'timeout not reported, saw: '..tostring(f.message:GetText()))
 assert(not ra.C.PlanAuthorized(sessionOf(ra,'Bob').state,ra.env.ShirsRaidBuilderDB.peerLinks,ra.wall,ra.now),'timed-out session authorized')
 ra:click(f.recipientButtons[1]); ra:click(f.sendButton); pump(net,40)
 assert(count(net,'PLAN')==0 and not f.batches,'plan sent after a timed-out refresh')
end

-- Boundary: the receiver rejects the invitation; no plan follows.
do
 local net=rig({'Alice','Bob'}); local ra,rb=net.list[1],net.list[2]
 link(ra,'Bob'); ra.env.ShirsRaidBuilderMainFrame:Show(); withPlan(ra)
 rb.env.ShirsRaidBuilderMainFrame:Show(); age(net) -- Bob holds no approval for Alice
 shareClick(ra); local f=ra.C.planShareFrame
 pump(net,12)
 local prompt=rb.C.peerPrompt
 assert(prompt and prompt:IsShown(),'receiver approval prompt missing')
 rb:click(prompt.rejectButton); pump(net,20)
 assert(count(net,'REJECT','alice')==1,'receiver did not send REJECT')
 assert(failed(f),'rejection not reported, saw: '..tostring(f.message:GetText()))
 assert(sessionOf(ra,'Bob').state.phase=='disabled','rejected session still open')
 ra:click(f.recipientButtons[1]); ra:click(f.sendButton); pump(net,40)
 assert(count(net,'PLAN')==0,'plan sent after rejection')
end

-- Boundary: whisper transport failure aborts the refresh; nothing reaches the wire.
do
 local net=rig({'Alice','Bob'}); local ra,rb=net.list[1],net.list[2]
 staleLink(net,ra,rb); age(net); withPlan(ra); net.broken['Alice']=true
 shareClick(ra); local f=ra.C.planShareFrame
 pump(net,12)
 assert(table.getn(net.wire)==0,'transport failure still recorded a whisper')
 assert(failed(f),'transport failure not reported, saw: '..tostring(f.message:GetText()))
 assert(sessionOf(ra,'Bob').state.phase=='disabled','failed transport left a live session')
 net.broken['Alice']=nil
 ra:click(f.recipientButtons[1]); ra:click(f.sendButton); pump(net,40)
 assert(count(net,'PLAN')==0 and not f.batches,'plan sent after transport failure')
end

-- Boundary: cancelling the popup before dispatch sends nothing; after dispatch it ends the session.
do
 local net=rig({'Alice','Bob'}); local ra,rb=net.list[1],net.list[2]
 staleLink(net,ra,rb); age(net); withPlan(ra)
 shareClick(ra); local f=ra.C.planShareFrame
 pump(net,2); ra:click(f.cancelButton); pump(net,60)
 assert(count(net,'INVITE')==0,'cancel before dispatch still sent the INVITE')
 assert(sessionOf(ra,'Bob').state.phase=='disabled')
 shareClick(ra); f=ra.C.planShareFrame; pump(net,8)
 assert(count(net,'INVITE','bob')==1,'second open did not invite')
 ra:click(f.cancelButton); pump(net,60)
 assert(sessionOf(ra,'Bob').state.phase~='linked' and count(net,'PLAN')==0,'cancelled refresh completed or sent a plan')
end

-- Boundary: revoked or never-approved peers are neither listed nor refreshed.
do
 local net=rig({'Alice','Bob'}); local ra,rb=net.list[1],net.list[2]
 staleLink(net,ra,rb); age(net); withPlan(ra)
 ra.C.LinkForget(ra.env.ShirsRaidBuilderDB.peerLinks,'Alice','Bob','FixtureRealm',false)
 shareClick(ra); local f=ra.C.planShareFrame
 assert(table.getn(f.recipients)==0 and not next(f.refresh),'revoked peer listed or refreshed')
 pump(net,40); assert(table.getn(net.wire)==0,'revoked peer received a whisper')
 f:Hide()
 local unknown=rig({'Alice','Zed'}); local ua=unknown.list[1]
 age(unknown); withPlan(ua); shareClick(ua); f=ua.C.planShareFrame
 assert(table.getn(f.recipients)==0 and not next(f.refresh),'unknown peer listed or refreshed')
 pump(unknown,40); assert(table.getn(unknown.wire)==0,'unknown peer received a whisper')
end

-- Boundary: repeated Share clicks retain the single in-flight invitation.
do
 local net=rig({'Alice','Bob'}); local ra,rb=net.list[1],net.list[2]
 staleLink(net,ra,rb); age(net); withPlan(ra)
 shareClick(ra); local f=ra.C.planShareFrame
 shareClick(ra); pump(net,1); shareClick(ra); pump(net,8); shareClick(ra); pump(net,4); shareClick(ra)
 assert(ra.C.planShareFrame==f,'repeated click replaced the popup')
 pump(net,60)
 assert(count(net,'INVITE')==1,'repeated clicks sent '..count(net,'INVITE')..' INVITEs')
 assert(count(net,'PLAN')==0,'repeated clicks sent a plan')
end

-- Boundary: refreshing one recipient leaves an unrelated in-flight session untouched.
do
 local net=rig({'Alice','Bob','Carol'}); local ra,rb=net.list[1],net.list[2]
 staleLink(net,ra,rb); age(net); withPlan(ra)
 local other=ra.C.PeerNew('Alice','Carol','FixtureRealm')
 other.phase='waiting'; other.a='300001'; other.started=ra.now; other.deadline=ra.now+60; other.expires=ra.wall+60
 local osession=ra.C.SyncSelect(other,true); ra.C.SyncActivate(osession)
 shareClick(ra); local f=ra.C.planShareFrame
 assert(ra.C.activeSession==osession and osession.state==other,'refresh stole the unrelated session')
 assert(other.phase=='waiting' and other.a=='300001','refresh altered the unrelated session')
 pump(net,8)
 assert(count(net,'INVITE','carol')==0,'refresh sent traffic for the unrelated session')
 assert(other.phase=='waiting' and other.a=='300001','pump altered the unrelated session')
 local activeBefore=ra.C.activeSession
 ra:click(f.cancelButton)
 assert(ra.C.activeSession==activeBefore,'cancel changed the active session')
 assert(other.phase=='waiting' and other.a=='300001','cancel disturbed the unrelated session')
end

-- Boundary: with one healthy and one stale recipient, Send refuses everything until the stale one authenticates.
do
 local net=rig({'Alice','Bob','Carol'}); local ra,rb,rc=net.list[1],net.list[2],net.list[3]
 staleLink(net,ra,rb); staleLink(net,ra,rc); age(net); withPlan(ra)
 renew(net,ra,rb) -- Bob stays healthy, Carol is stale
 shareClick(ra); local f=ra.C.planShareFrame
 assert(table.getn(f.recipients)==2,'both recipients must be listed')
 ra:click(f.recipientButtons[1]); ra:click(f.recipientButtons[2]); ra:click(f.sendButton)
 assert(not f.batches and string.find(f.message:GetText(),'unavailable',1,true),'Send did not refuse while Carol was stale, saw: '..tostring(f.message:GetText()))
 assert(not sessionOf(ra,'Bob').state.planOut,'healthy recipient was queued despite the refusal')
 pump(net,3); ra:click(f.sendButton)
 assert(not f.batches and count(net,'PLAN')==0,'Send proceeded mid-refresh')
 pump(net,60)
 assert(count(net,'INVITE','carol')==1 and count(net,'INVITE','bob')==0,'only the stale recipient may be refreshed')
 assert(ra.C.PlanAuthorized(sessionOf(ra,'Carol').state,ra.env.ShirsRaidBuilderDB.peerLinks,ra.wall,ra.now),'Carol did not authenticate')
 assert(count(net,'PLAN')==0,'refresh sent a plan')
 ra:click(f.sendButton); assert(f.batches,'Send refused after every selected recipient authenticated')
 -- 80 ticks (20s): approval must be asserted inside the existing 60s auth lifetime
 pump(net,80)
 rb.C.SyncStore(); rc.C.SyncStore()
 assert(count(net,'PLAN','bob')>0 and count(net,'PLAN','carol')>0,'authenticated Send did not reach both recipients')
 assert(sessionOf(rb,'Alice').state.planProposal and sessionOf(rc,'Alice').state.planProposal,'recipients did not receive the plan')
end
-- Selection, not opening, chooses whom to refresh: with two stale recipients the
-- second row alone must drive the SRBLINK2 handshake and the plan send.
do
 local net=rig({'Alice','Bob','Carol'}); local ra,rb,rc=net.list[1],net.list[2],net.list[3]
 staleLink(net,ra,rb); staleLink(net,ra,rc); age(net); withPlan(ra)
 shareClick(ra); local f=ra.C.planShareFrame
 assert(table.getn(f.recipients)==2 and string.find(f.recipientButtons[1].recipient.key,'bob',1,true) and string.find(f.recipientButtons[2].recipient.key,'carol',1,true),'row order must be Bob then Carol')
 pump(net,8)
 assert(count(net,'INVITE')==0,'opening the popup refreshed a recipient before any selection, saw '..count(net,'INVITE'))
 ra:click(f.recipientButtons[2])
 assert(f.selected[f.recipientButtons[2].recipient.key] and not f.selected[f.recipientButtons[1].recipient.key],'only the second row may be selected')
 pump(net,8)
 assert(count(net,'INVITE','carol')==1,'selected second recipient was not invited, saw '..count(net,'INVITE','carol'))
 assert(count(net,'INVITE','bob')==0,'unselected first recipient was used as the refresh fallback')
 pump(net,60)
 assert(ra.C.PlanAuthorized(sessionOf(ra,'Carol').state,ra.env.ShirsRaidBuilderDB.peerLinks,ra.wall,ra.now),'Carol did not authenticate')
 assert(not ra.C.PlanAuthorized(sessionOf(ra,'Bob').state,ra.env.ShirsRaidBuilderDB.peerLinks,ra.wall,ra.now),'unselected Bob authenticated')
 assert(count(net,'INVITE','bob')==0 and count(net,'PLAN')==0,'refresh sent a plan or touched Bob')
 ra:click(f.sendButton); assert(f.batches and table.getn(f.batches)==1,'Send refused or queued the wrong recipients after Carol authenticated')
 pump(net,80); rc.C.SyncStore()
 assert(count(net,'PLAN','carol')>0 and count(net,'PLAN','bob')==0,'plan must go only to the selected second recipient')
 assert(sessionOf(rc,'Alice').state.planProposal and not (sessionOf(rb,'Alice') and sessionOf(rb,'Alice').state.planProposal),'only Carol may hold a proposal')
 rc:fire(rc.C.peerDriver,'OnUpdate',0.25)
 local prompt=rc.C.planReceiveFrame; assert(prompt and prompt:IsShown(),'Carol approval prompt missing')
 assert(not rc.env.ShirsRaidBuilderDB.presets.Shared,'plan merged before receiver approval')
end
-- Share while the SAME recipient's link handshake is already in
-- flight (started externally from Link Account, before Share opens) observes that
-- handshake instead of marking the recipient busy. It never restarts, cancels or
-- replaces the borrowed handshake and never sends a plan without an explicit Send.
local function says(f,word) return string.find(string.lower(f.message:GetText()),word,1,true) end
local function borrowed(withCarol)
 local net=rig(withCarol and {'Alice','Bob','Carol'} or {'Alice','Bob'}); local ra,rb=net.list[1],net.list[2]
 link(ra,'Bob'); ra.env.ShirsRaidBuilderMainFrame:Show(); rb.env.ShirsRaidBuilderMainFrame:Show() -- Bob holds no approval for Alice
 withPlan(ra); age(net)
 local other
 if withCarol then
  other=ra.C.PeerNew('Alice','Carol','FixtureRealm')
  other.phase='waiting'; other.a='300001'; other.started=ra.now; other.deadline=ra.now+400; other.expires=ra.wall+400
  ra.C.SyncActivate(ra.C.SyncSelect(other,true))
 end
 -- The external owner: the real Link Account Pair click, well before Share opens.
 ra.C.OpenPeerPOC(); ra.C.peerPanel.nameInput:SetText('Bob'); ra:click(ra.C.peerPanel.pairButton)
 pump(net,12)
 local s=sessionOf(ra,'Bob').state
 assert(s.phase=='waiting' and count(net,'INVITE','bob')==1,'external handshake fixture did not reach waiting, phase '..tostring(s.phase))
 assert(rb.C.peerPrompt and rb.C.peerPrompt:IsShown(),'receiver approval prompt missing in fixture')
 return net,ra,rb,s.a,other
end
local function bobState(ra) return sessionOf(ra,'Bob').state end
local function stillBorrowed(net,ra,a0)
 local s=bobState(ra)
 assert(s.phase=='waiting' and s.a==a0,'borrowed handshake was cancelled or replaced, phase '..tostring(s.phase))
 assert(count(net,'INVITE')==1,'borrowed handshake was restarted: '..count(net,'INVITE')..' INVITEs')
end

-- Observe, wait, then explicit Send and explicit Copy after the receiver approves.
do
 local net,ra,rb,a0,other=borrowed(true)
 shareClick(ra); local f=ra.C.planShareFrame
 assert(f:IsShown() and table.getn(f.recipients)==1,'share popup did not open for the in-flight recipient')
 assert(says(f,'waiting'),'Share must show waiting guidance for the in-flight handshake, saw: '..tostring(f.message:GetText()))
 assert(not says(f,'busy') and not says(f,'unavailable'),'in-flight handshake reported as busy/unavailable: '..tostring(f.message:GetText()))
 stillBorrowed(net,ra,a0)
 ra:click(f.recipientButtons[1]); ra:click(f.sendButton); pump(net,4)
 assert(says(f,'waiting') and not says(f,'unavailable'),'Send during approval must keep waiting guidance, saw: '..tostring(f.message:GetText()))
 assert(not f.batches and not bobState(ra).planOut and count(net,'PLAN')==0,'Send during approval queued a plan')
 shareClick(ra); ra:click(ra:button(ra.env.ShirsRaidBuilderMainFrame,'Share Current Plan')); pump(net,4) -- repeated clicks
 stillBorrowed(net,ra,a0)
 assert(count(net,'ACCEPT')==0 and count(net,'CONFIRM')==0 and count(net,'READY')==0,'handshake advanced without the receiver')
 rb:click(rb.C.peerPrompt.acceptButton); pump(net,40)
 local s=bobState(ra)
 assert(s.phase=='linked' and s.a==a0 and ra.C.PlanAuthorized(s,ra.env.ShirsRaidBuilderDB.peerLinks,ra.wall,ra.now),'observed handshake did not complete on the same nonce')
 assert(count(net,'INVITE')==1 and count(net,'ACCEPT')==1 and count(net,'CONFIRM')==1 and count(net,'READY')==1,'handshake messages were duplicated or missing')
 assert(says(f,'ready'),'popup must report ready after the observed handshake, saw: '..tostring(f.message:GetText()))
 assert(count(net,'PLAN')==0 and not f.batches,'plan sent without an explicit Send after readiness')
 ra:click(f.sendButton); assert(f.batches and table.getn(f.batches)==1,'explicit Send after readiness was refused')
 pump(net,80)
 assert(count(net,'PLAN','bob')>0 and sessionOf(rb,'Alice').state.planProposal,'explicit Send did not deliver the plan')
 rb:fire(rb.C.peerDriver,'OnUpdate',0.25)
 local prompt=rb.C.planReceiveFrame; assert(prompt and prompt:IsShown(),'receiver approval prompt missing')
 assert(not rb.env.ShirsRaidBuilderDB.presets.Observed,'plan imported before the receiver chose Copy')
 prompt.destination:SetText('Observed'); rb:click(prompt.copyButton)
 assert(rb.env.ShirsRaidBuilderDB.presets.Observed.entries[1].charName=='Companion','explicit Copy failed')
 assert(other.phase=='waiting' and other.a=='300001' and count(net,'INVITE','carol')==0,'unrelated exchange was touched')
end

-- Closing or deselecting in Share never cancels a handshake Share did not start.
do
 local net,ra,rb,a0=borrowed(false)
 shareClick(ra); local f=ra.C.planShareFrame
 ra:click(f.recipientButtons[1]); ra:click(f.recipientButtons[1]) -- select, then deselect
 stillBorrowed(net,ra,a0); assert(says(f,'waiting'),'deselect lost the waiting guidance')
 ra:click(f.recipientButtons[1]); ra:click(f.cancelButton); pump(net,4)
 stillBorrowed(net,ra,a0); assert(rb.C.peerPrompt:IsShown(),'popup close withdrew the receiver approval prompt')
 rb:click(rb.C.peerPrompt.acceptButton); pump(net,40)
 local s=bobState(ra)
 assert(s.phase=='linked' and s.a==a0 and ra.C.PlanAuthorized(s,ra.env.ShirsRaidBuilderDB.peerLinks,ra.wall,ra.now),'externally owned handshake did not complete after popup close')
 assert(count(net,'INVITE')==1 and count(net,'PLAN')==0,'close restarted the handshake or sent a plan')
end

-- Rejection and timeout of the borrowed handshake fail clearly and never send a plan.
do
 local net,ra,rb,a0=borrowed(false)
 shareClick(ra); local f=ra.C.planShareFrame; ra:click(f.recipientButtons[1]); ra:click(f.sendButton)
 rb:click(rb.C.peerPrompt.rejectButton); pump(net,20)
 assert(count(net,'REJECT','alice')==1 and bobState(ra).phase=='disabled','fixture: receiver rejection did not reach the sender')
 assert(says(f,'failed') and not says(f,'waiting'),'rejection not reported as failed, saw: '..tostring(f.message:GetText()))
 ra:click(f.sendButton); pump(net,40)
 assert(count(net,'PLAN')==0 and not f.batches,'plan sent after rejection of the borrowed handshake')
end
do
 local net,ra,rb,a0=borrowed(false)
 shareClick(ra); local f=ra.C.planShareFrame; ra:click(f.recipientButtons[1])
 pump(net,300) -- the receiver never answers
 assert(says(f,'failed') and not says(f,'waiting'),'timeout not reported as failed, saw: '..tostring(f.message:GetText()))
 assert(not ra.C.PlanAuthorized(bobState(ra),ra.env.ShirsRaidBuilderDB.peerLinks,ra.wall,ra.now),'timed-out handshake authorized')
 ra:click(f.sendButton); pump(net,40)
 assert(count(net,'PLAN')==0 and not f.batches,'plan sent after timeout of the borrowed handshake')
end

-- A replaced handshake (new nonce) must not authorize the observation of the old one,
-- even after the NEW handshake is approved and authenticated: the failed old popup
-- may not send until it is closed and reopened.
do
 local net,ra,rb,a0=borrowed(false)
 shareClick(ra); local f=ra.C.planShareFrame; ra:click(f.recipientButtons[1])
 -- Bob withdraws the old prompt (real OnHide, no packet) and outwaits his invite throttle.
 rb.C.peerPrompt:Hide(); pump(net,24)
 assert(bobState(ra).phase=='waiting' and bobState(ra).a==a0,'fixture: old handshake changed before replacement')
 ra:click(ra.C.peerPanel.cancelButton); ra:click(ra.C.peerPanel.pairButton) -- owner replaces it
 pump(net,12)
 local a1=bobState(ra).a
 assert(a1 and a1~=a0 and bobState(ra).phase=='waiting','fixture: replacement handshake has no new nonce')
 assert(rb.C.peerPrompt and rb.C.peerPrompt:IsShown(),'fixture: Bob never received the NEW invitation')
 assert(says(f,'failed'),'replaced handshake must fail the old observation, saw: '..tostring(f.message:GetText()))
 rb:click(rb.C.peerPrompt.acceptButton); pump(net,40) -- Bob explicitly accepts the NEW session
 local s=bobState(ra)
 assert(s.phase=='linked' and s.a==a1 and ra.C.PlanAuthorized(s,ra.env.ShirsRaidBuilderDB.peerLinks,ra.wall,ra.now),'fixture: new session not authorized')
 assert(says(f,'failed') and not says(f,'ready'),'old observation changed outcome under new auth: '..tostring(f.message:GetText()))
 assert(count(net,'PLAN')==0,'plan sent before any Send')
 ra:click(f.sendButton); pump(net,40)
 assert(not f.batches and not bobState(ra).planOut and count(net,'PLAN')==0,'Send from the failed old observation queued a plan under the new session')
 -- Only a fresh popup (close and reopen) may send, and only on an explicit Send.
 ra:click(f.cancelButton); shareClick(ra); f=ra.C.planShareFrame
 ra:click(f.recipientButtons[1]); assert(not f.batches and count(net,'PLAN')==0,'reopen sent without Send')
 ra:click(f.sendButton); assert(f.batches,'explicit Send after reopen was refused')
end
-- Invariants: with several recipients, selecting a row whose
-- handshake is already running borrows it; only a handshake Share itself started is owned.
do
 local net=rig({'Alice','Bob','Carol'}); local ra,rb,rc=net.list[1],net.list[2],net.list[3]
 link(ra,'Bob'); link(ra,'Carol'); link(rc,'Alice'); rc.env.ShirsRaidBuilderMainFrame:Hide()
 ra.env.ShirsRaidBuilderMainFrame:Show(); rb.env.ShirsRaidBuilderMainFrame:Show(); withPlan(ra); age(net)
 ra.C.OpenPeerPOC(); ra.C.peerPanel.nameInput:SetText('Bob'); ra:click(ra.C.peerPanel.pairButton); pump(net,12)
 local a0=bobState(ra).a
 assert(bobState(ra).phase=='waiting' and count(net,'INVITE','bob')==1,'fixture: external Bob handshake not waiting')
 shareClick(ra); local f=ra.C.planShareFrame
 assert(table.getn(f.recipients)==2 and not next(f.refresh),'opening with several recipients must not start or observe anything')
 local bobKey=f.recipientButtons[1].recipient.key; local carolKey=f.recipientButtons[2].recipient.key
 assert(string.find(bobKey,'bob',1,true) and string.find(carolKey,'carol',1,true),'row order must be Bob then Carol')
 ra:click(f.recipientButtons[1])
 local e=f.refresh[bobKey]
 assert(e and e.borrowed and e.status=='pending' and not e.owned,'selecting the in-flight row must borrow, not own, the handshake')
 assert(says(f,'waiting'),'borrowed selection needs waiting guidance, saw: '..tostring(f.message:GetText()))
 ra:click(f.recipientButtons[1]); stillBorrowed(net,ra,a0) -- deselect
 assert(f.refresh[bobKey].status=='pending','deselect dropped the observation')
 ra:click(f.recipientButtons[1]); assert(f.refresh[bobKey]==e,'reselect replaced the borrowed entry'); stillBorrowed(net,ra,a0)
 -- Selecting Carol starts an owned refresh; deselecting it cancels only that one.
 ra:click(f.recipientButtons[2])
 local ce=f.refresh[carolKey]; assert(ce and ce.owned and not ce.borrowed and ce.status=='pending','Carol refresh must be owned')
 ra:click(f.recipientButtons[2])
 assert(ce.status=='cancelled' and sessionOf(ra,'Carol').state.phase=='disabled','owned refresh was not cancelled on deselect')
 pump(net,8); stillBorrowed(net,ra,a0)
 assert(count(net,'INVITE','carol')==0 and count(net,'PLAN')==0,'cancelled owned refresh still sent traffic')
 assert(f.selected[bobKey],'fixture: Bob row should still be selected'); ra:click(f.sendButton); pump(net,4)
 assert(not f.batches and says(f,'waiting') and count(net,'PLAN')==0,'Send with a borrowed recipient pending must only show waiting')
 ra:click(f.cancelButton); pump(net,4); stillBorrowed(net,ra,a0)
 rb:click(rb.C.peerPrompt.acceptButton); pump(net,40)
 assert(bobState(ra).phase=='linked' and bobState(ra).a==a0 and count(net,'INVITE')==1 and count(net,'PLAN')==0,'borrowed handshake did not finish untouched')
end

-- A session waiting on this side's own explicit incoming approval is
-- observed like any other in-flight handshake; Share neither answers nor drops it.
do
 local net=rig({'Alice','Bob'}); local ra,rb=net.list[1],net.list[2]
 link(ra,'Bob'); ra.env.ShirsRaidBuilderMainFrame:Show(); withPlan(ra); age(net)
 local session=sessionOf(ra,'Bob'); ra.C.SyncActivate(session)
 local s=session.state
 s.phase='approval'; s.a='400001'; s.started=ra.now; s.deadline=ra.now+400; s.expires=ra.wall+400
 ra.C.SyncStore(); pump(net,2)
 assert(ra.C.peerPrompt and ra.C.peerPrompt:IsShown() and bobState(ra).phase=='approval','fixture: incoming approval prompt missing')
 shareClick(ra); local f=ra.C.planShareFrame
 assert(says(f,'waiting') and not says(f,'busy'),'approval phase must show waiting guidance, saw: '..tostring(f.message:GetText()))
 ra:click(f.recipientButtons[1]); ra:click(f.sendButton); pump(net,4)
 assert(not f.batches and says(f,'waiting') and count(net,'PLAN')==0,'Send during incoming approval queued a plan')
 ra:click(f.cancelButton); pump(net,4)
 assert(bobState(ra).phase=='approval' and bobState(ra).a=='400001' and ra.C.peerPrompt:IsShown(),'Share close dropped the incoming approval')
 assert(table.getn(net.wire)==0,'Share answered or restarted the incoming approval, saw '..table.getn(net.wire)..' messages')
end
print("Shir's Raid Builder plan share UI tests: PASS")
