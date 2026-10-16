-- Registered Refresh, real four-message trust handshake and native account reads.
-- No mocked success callbacks, live input, spending, or remote installation.
local f=assert(io.open('test_planner_linked_quotes.lua'));local src=f:read('*a');f:close()
local at=assert(string.find(src,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(src,1,at-1)..'\nreturn fixture'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local function normal(name,tier,race)return {kind='normal',account=name,tier=tier or 't3r',class='mage',role='rdps',race=race or 'gnome',gender='female',spec='fire'}end
local function plan(h,rows)
 local p=h:preset();p.entries={};for i=1,40 do p.entries[i]=rows[i] or {kind='empty'}end
 p.entries[40]={kind='player',charName=h.name,class='warrior',role='tank'};p.plannerPlayerSlot=40;h.env.RefreshComposition();return p
end
local function clear(h)
 h.C.peerSessions={};h.C.activeSession=nil;h.C.peerState=nil;h.C.peerPending=nil;h.C.peerAutoAttempted=nil
end
local function refresh(h)h:click(h.env.ShirsRaidBuilderMainFrame.syncButton)end
local function settle(h,pump)
 for i=1,400 do pump(0.25);if h.C.visiblePrice and h.C.visiblePrice.phase=='done' then return end end
 error('native Refresh did not settle: '..tostring(h.C.visiblePriceWhy)..' phase='..tostring(h.C.visiblePrice and h.C.visiblePrice.phase))
end
local function total(h,known,unknown)
 local w=assert(h.C.visiblePrice,'visible continuation lost');local e=assert(w.estimate,'no estimate; phase='..tostring(w.phase))
 assert(e.known==known and e.unknown==unknown,'priced='..e.known..' unknown='..e.unknown..' reason='..tostring(w.reason))
 return e
end
local function safe(h)
 assert(not h.C.handAuthority and not h.C.handRunPlan,'metadata granted spending authority')
 for _,p in ipairs(h.history)do assert(not h.C.HandParse(p.text),'metadata sent hiring handoff')end
end

test('cold saved-link Refresh completes every real handshake before collecting own and two linked accounts',function()
 local a,b,c,pump=fixture();plan(a,{normal('Alice'),normal('Bob'),normal('Carol')})
 for _,h in ipairs({a,b,c})do clear(h)end
 local trace={};local collect=a.C.VisiblePriceCollect
 a.C.VisiblePriceCollect=function(w)
  for key,session in pairs(a.C.peerSessions)do table.insert(trace,key..'='..tostring(session.state.phase))end
  collect(w)
 end
 refresh(a);pump(30);total(a,3,0)
 assert(table.getn(a.quoteReads)==1 and table.getn(b.quoteReads)==1 and table.getn(c.quoteReads)==1,table.concat(trace,','))
 for _,h in ipairs({a,b,c})do safe(h)end
end)

test('Refresh must wait through confirm-sent and a delayed native READY instead of dropping linked rows',function()
 local a,b,c,pump,open,emit=fixture();plan(a,{normal('Alice'),normal('Bob')})
 clear(a);clear(b);local delayed;local send=b.env.SendChatMessage
 b.env.SendChatMessage=function(text,route,language,target)
  local p=b.C.LinkParse(text)
  if p and p.kind=='READY' and target=='alice' then delayed=text;return end
  return send(text,route,language,target)
 end
 refresh(a);pump(4)
 assert(delayed,'fixture did not hold native READY');assert(not a.C.visiblePrice or a.C.visiblePrice.phase~='done','Refresh completed before READY')
 assert(table.getn(a.quoteReads)==0 and table.getn(b.quoteReads)==0,'quotes started before trust handshake finished')
 emit(a,'CHAT_MSG_WHISPER',delayed,'Bob');pump(26);total(a,2,0)
end)

test('busy native refresh is borrowed and finishes once without duplicate GET or a lost account',function()
 local a,b,c,pump=fixture();plan(a,{normal('Alice'),normal('Bob'),normal('Carol')})
 a.C.SyncRefreshAll();pump(0.25);refresh(a);refresh(a);pump(30);total(a,3,0)
 assert(table.getn(a.quoteReads)==1 and table.getn(b.quoteReads)==1 and table.getn(c.quoteReads)==1,'busy refresh duplicated or dropped quotes')
end)

test('unavailable first linked account does not prevent later selected accounts getting fresh quotes',function()
 local a,b,c,pump=fixture();plan(a,{normal('Bob'),normal('Alice'),normal('Carol')})
 b.C.QuoteEvent=function()end;refresh(a);settle(a,pump);total(a,2,1)
 assert(table.getn(a.quoteReads)==1 and table.getn(c.quoteReads)==1,'one unsupported endpoint aborted unrelated rows')
 safe(a);safe(c)
end)

test('expired links renew on explicit Refresh and never require a second click',function()
 local a,b,c,pump=fixture();plan(a,{normal('Alice'),normal('Bob'),normal('Carol')});pump(65)
 refresh(a);pump(30);total(a,3,0)
 assert(table.getn(b.quoteReads)==1 and table.getn(c.quoteReads)==1,'expired session lost its continuation')
end)

test('remote alt quotes use that character current count and race not the online endpoint count',function()
 local a,b,c,pump=fixture();b.roster='Bob:warrior:t2d:t3r:A:0:60:3:4 Bobby:mage:t2d:t3r:A:0:60:1:4'
 b.prices.Bobby=600;b.counts.Bob=3;b.counts.Bobby=1
 -- Populate the new source through native account exchange before selecting it.
 a.C.SyncRefreshAll()
 for i=1,240 do
  pump(0.25);local session=a.C.peerSessions['FixtureRealm;bob'];local s=session and session.state
  local found=false;for _,row in ipairs(s and s.remoteLicense and s.remoteLicense.entries or {})do if row.name=='Bobby' then found=true end end
  if found and not session.pending and not s.licenseWait and not s.licenseServe and not s.licenseOut and not s.raidWait and not s.raidServe and not s.raidOut then break end
 end
 local found=false;for _,s in ipairs(a.C.PlannerReadSources())do if s.name=='Bobby' then found=true end end
 assert(found,'native account read did not publish the selected alt')
 for i=1,240 do local s=a.C.peerSessions['FixtureRealm;bob'].state;if s.expires-a.wall<=12 then break end;pump(0.25)end
 plan(a,{normal('Bobby'),normal('Bob'),normal('Bobby')})
 refresh(a);settle(a,pump);local e=total(a,3,0)
 local q=a.C.visiblePrice.quotes['2222222222222222:bobby:t3r'];assert(q and q.count==1 and q.name=='Bobby' and q.accountId=='2222222222222222')
 assert(e.totalCopper==2600,'wrong per-character ordinal; total='..e.totalCopper)
 assert(table.getn(b.quoteReads)==2,'not one quote per exact source/licence')
 safe(a);safe(b)
end)

test('cold offline first endpoint stays unknown without expiring the other required account',function()
 local a,b,c,pump=fixture();plan(a,{normal('Bob'),normal('Alice'),normal('Carol')})
 for _,h in ipairs({a,b,c})do clear(h)end
 b.env.SendChatMessage=function()end
 local trust=a.C.PlannerCopy(a.env.ShirsRaidBuilderDB.peerLinks);local before=table.getn(a.history)
 refresh(a);settle(a,pump);total(a,2,1)
 assert(table.getn(b.quoteReads)==0 and table.getn(a.quoteReads)==1 and table.getn(c.quoteReads)==1,'offline endpoint suppressed available accounts')
 local invitations=0;for i=before+1,table.getn(a.history)do local p=a.C.LinkParse(a.history[i].text);if p and p.kind=='INVITE'and p.target=='carol'then invitations=invitations+1 end end
 assert(invitations==2,'ready account renewal was absent or unbounded')
 local sent=table.getn(a.history);pump(90);assert(table.getn(a.history)==sent,'completed batch became a background keepalive')
 assert(a.C.PlannerEqual(trust,a.env.ShirsRaidBuilderDB.peerLinks),'Refresh added trust');safe(a);safe(c)
end)

test('untrusted or colliding account identities cannot borrow another source price',function()
 for _,mode in ipairs({'untrusted','collision'})do
  local a,b,c,pump=fixture()
  if mode=='untrusted'then
   for key,link in pairs(a.env.ShirsRaidBuilderDB.peerLinks)do if link.peer=='bob'then a.env.ShirsRaidBuilderDB.peerLinks[key]=nil end end
  else
   c.roster='Carol:warrior:t2d:t3r:A:0:60:0:4 Bob:mage:t2d:t3r:A:0:60:0:4';c.prices.Bob=1
   a.C.SyncRefreshAll();pump(20)
  end
  plan(a,{normal('Bob'),normal('Alice'),normal('Carol')});local trust=a.C.PlannerCopy(a.env.ShirsRaidBuilderDB.peerLinks)
  refresh(a);settle(a,pump);local e=total(a,2,1)
  assert(e.totalCopper==10000 and table.getn(b.quoteReads)==0,'ambiguous source got an authoritative quote')
  assert(a.C.PlannerEqual(trust,a.env.ShirsRaidBuilderDB.peerLinks),'quote created approval');safe(a)
 end
end)

test('visible native wait rejects spoofed account character tier nonce sender and old protocol replies',function()
 local a,b,c,pump,open,emit,state=fixture();b.noReply=true;plan(a,{normal('Bob'),normal('Alice'),normal('Carol')});refresh(a)
 for i=1,160 do pump(0.25);if b.C.plannerQuoteFlight then break end end
 local w=assert(a.C.plannerQuotes and a.C.plannerQuotes.wait,'no native peer wait')
 local function packet(field,value)
  local q={nonce=w.nonce,requester=w.requester,owner=w.owner,name=w.name,tier=w.tier};if field then q[field]=value end
  return assert(b.C.QuotePacket(state(b,'Alice'),'P',q,'1:1:1:1'))
 end
 local good=packet()
 for _,sender in ipairs({'Carol','Mallory','Alice'})do emit(a,'CHAT_MSG_WHISPER',good,sender)end
 for _,change in ipairs({{'owner','3333333333333333'},{'requester','9999999999999999'},{'name','Carol'},{'tier','t2r'},{'nonce','999999'}})do emit(a,'CHAT_MSG_WHISPER',packet(change[1],change[2]),'Bob')end
 emit(a,'CHAT_MSG_WHISPER',string.gsub(good,'SRBQUOTE1','SRBQUOTE2'),'Bob')
 emit(a,'CHAT_MSG_WHISPER',string.gsub(good,';'..w.a..';',';999999;'),'Bob')
 assert(a.C.plannerQuotes.wait==w and not w.price,'unmatched reply changed visible authority')
 emit(b,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE Bob:1000:1000:0:0:1000:1000:0:4','nexus')
 settle(a,pump);local e=total(a,3,0);assert(e.totalCopper==11000,'forged discount reached footer');safe(a)
end)

test('stale native metadata for the first account does not suppress later fresh quotes',function()
 local a,b,c,pump,open,emit,state=fixture();plan(a,{normal('Bob'),normal('Alice'),normal('Carol')})
 local send=b.env.SendChatMessage
 b.env.SendChatMessage=function(text,route,language,target)
  local p=b.C.QuoteParse(text)
  if p and p.kind=='M'then text=assert(b.C.QuotePacket(state(b,'Alice'),'M',p,'0:0:0:4:'..(b.wall-31)))end
  return send(text,route,language,target)
 end
 refresh(a);settle(a,pump);total(a,2,1);assert(table.getn(a.quoteReads)==1 and table.getn(c.quoteReads)==1,'stale first reply aborted later rows');safe(a)
end)

test('native Stop drains the exact old flight and a fresh Refresh can retry all required accounts',function()
 local a,b,c,pump,open,emit=fixture();plan(a,{normal('Bob'),normal('Alice'),normal('Carol')});b.noReply=true;refresh(a)
 for i=1,160 do pump(0.25);if b.C.plannerQuoteFlight then break end end
 assert(b.C.plannerQuoteFlight,'native peer read absent');a:click(a.env.ShirsRaidBuilderMainFrame.stopBtn);pump(1)
 assert(not a.C.visiblePrice and b.C.plannerQuoteFlight.drain,'Stop lost drain fence')
 emit(b,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE Bob:1:1:0:0:1:1:0:4','nexus');pump(1)
 assert(not b.C.plannerQuoteFlight and not a.C.visiblePrice,'late stopped reply became current')
 b.noReply=false;refresh(a);settle(a,pump);local e=total(a,3,0)
 assert(e.totalCopper==11000 and table.getn(b.quoteReads)==2,'retry reused cancelled result or skipped source');safe(a);safe(b)
end)

print("Shir's Raid Builder native visible sync tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'native visible synchronization regressions failed')
