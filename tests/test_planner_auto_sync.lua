-- Native trusted handshake/account replies/quote driver; no main Refresh shortcut.
local file=assert(io.open('test_planner_linked_quotes.lua'));local src=file:read('*a');file:close()
local boundary=assert(string.find(src,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(src,1,boundary-1)..'\nreturn fixture'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local function expire(h)
 h.C.peerSessions={};h.C.activeSession=nil;h.C.peerState=nil;h.C.peerPending=nil;h.C.peerAutoAttempted=nil
 h.C.SyncRefreshAll=function() error('builder called main Refresh Synchronization') end
end
test('one Build renews a trusted stale link reads fresh accounts then quotes same request and creates plan',function()
 local a,b,c,pump,open=fixture();expire(a);local p=open(a,{Bob=true},2);p.nameInput:SetText('Automatic refresh');a:click(p.buildButton)
 assert(a.C.plannerSync and string.find(p.message:GetText(),'Synchronizing characters',1,true),'Build did not start native synchronization')
 assert(not p.proposal and not p.applyButton:IsEnabled() and table.getn(b.quoteReads)==0)
 pump(25);local r=assert(p.proposal,p.message:GetText());assert(r.normal==2 and table.getn(b.quoteReads)==1 and table.getn(a.quoteReads)==0,'continuation quoted twice or wrong source')
 assert(p.request.sources['2222222222222222:bob'].tier=='t3r' and p.request.counts['mage:rdps']==2,'selection changed while syncing')
 assert(string.find(p.previewText:GetText(),'Estimated total:',1,true) and not string.find(p.previewText:GetText(),'copper',1,true),'raw benchmark UI remains')
 assert(not string.find(p.previewText:GetText(),'next race quote',1,true) and not string.find(p.previewText:GetText(),'SRBQUOTE',1,true))
 a:click(p.applyButton);a.env.RefreshComposition();assert(a.env.ShirsRaidBuilderDB.currentPreset=='Automatic refresh')
 local fresh=a.C.PlannerCopy(a.env.ShirsRaidBuilderDB);assert(fresh.presets['Automatic refresh']);for _,h in ipairs({a,b,c}) do assert(not h.C.handAuthority and not h.C.handRunPlan) end
end)
test('authorized live link with stale account data refreshes once without re-pairing or main button',function()
 local a,b,c,pump,open,emit,state=fixture();local s=state(a,'Bob');s.remoteLicense.received=a.wall-61
 if a.C.remoteLicenses then a.C.remoteLicenses['FixtureRealm;bob'].received=a.wall-61 end
 a.C.SyncRefreshAll=function() error('main refresh called') end
 local before=s.a;local p=open(a,{Bob=true});a:click(p.buildButton);pump(25)
 assert(p.proposal,p.message:GetText());assert(state(a,'Bob').a==before,'fresh handshake restarted unnecessarily');assert(table.getn(b.quoteReads)==1)
end)
test('own account never starts linked sync',function()
 local a,b,c,pump,open=fixture();expire(a);local p=open(a,{Alice=true});a:click(p.buildButton);assert(not a.C.plannerSync);pump(3);assert(p.proposal,p.message:GetText())
end)
test('second Build cancels sync; later handshake/account replies cannot resume or save',function()
 local a,b,c,pump,open=fixture();expire(a);local p=open(a,{Bob=true});local before=a.C.PlannerCopy(a:preset())
 a:click(p.buildButton);assert(a.C.plannerSync,'no pending sync');a:click(p.buildButton);pump(25)
 assert(not a.C.plannerSync and not a.C.plannerQuotes and not p.proposal and table.getn(b.quoteReads)==0,'cancelled continuation restarted')
 assert(a.C.PlannerEqual(before,a:preset()))
end)
test('race source tier counts profile account and window changes cancel old continuation',function()
 for _,mode in ipairs({'race','source','tier','counts','profile','account','close'}) do
  local a,b,c,pump,open=fixture();expire(a);local p=open(a,{Bob=true});a:click(p.buildButton);assert(a.C.plannerSync,mode..' no pending sync')
  if mode=='race' then a.C.PlannerTab('counts');a:choose(p.classDefaults.mage.raceButton,'human')
  elseif mode=='source' then for _,row in ipairs(p.sourceRows) do if row.source.name=='Bob' then row.normalCheck:SetChecked(nil);a:fire(row.normalCheck,'OnClick') end end
  elseif mode=='tier' then p.request.sources['2222222222222222:bob'].tier='t2d';a.C.PlannerInvalidate()
  elseif mode=='counts' then p.countInputs['mage:rdps']:SetText('2')
  elseif mode=='profile' then a.env.ShirsRaidBuilderDB.currentPreset='Other'
  elseif mode=='account' then a.env.ShirsRaidBuilderDB.syncAccountId='9999999999999999'
  else a.C.ClosePlanner() end
  pump(25);assert(not p.proposal and not a.C.plannerSync and not a.C.plannerQuotes and table.getn(b.quoteReads)==0,mode..' retained old continuation')
 end
end)
test('untrusted offline and old quote versions stop visibly without hires or automatic trust',function()
 for _,mode in ipairs({'untrusted','offline','version'}) do
  local a,b,c,pump,open=fixture();local p=open(a,{Bob=true});local before=a.C.PlannerCopy(a:preset())
  if mode=='untrusted' then a.env.ShirsRaidBuilderDB.peerLinks={} elseif mode=='offline' then expire(a);b.env.SendChatMessage=function() end else b.C.QuoteEvent=function() end end
  a:click(p.buildButton);pump(70)
  assert(not p.proposal and not a.C.plannerSync and not a.C.plannerQuotes,mode..' failed open')
  assert(not a.C.handAuthority and not b.C.handAuthority and a.C.PlannerEqual(before,a:preset()))
  local text=string.lower(p.message:GetText());assert(string.find(text,'trust',1,true) or string.find(text,'offline',1,true) or string.find(text,'updat',1,true) or string.find(text,'timeout',1,true),text)
 end
end)
print("Shir's Raid Builder automatic sync tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'automatic sync regressions failed')
