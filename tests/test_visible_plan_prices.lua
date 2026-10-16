-- Native Refresh -> account synchronization -> existing quote driver -> Hire footer.
-- Whole-module synthetic endpoints; never live game input, hiring or spending.
local f=assert(io.open('test_planner_linked_quotes.lua'));local src=f:read('*a');f:close()
local at=assert(string.find(src,"\ntest('mixed own",1,true));local fixture=assert(loadstring(string.sub(src,1,at-1)..'\nreturn fixture'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local function normal(name,tier,race)return {kind='normal',account=name,tier=tier or 't3r',class='mage',role='rdps',race=race or 'gnome',gender='female',spec='fire'} end
local function setPlan(h,rows)
 local p=h:preset();p.entries={};for i=1,40 do p.entries[i]=rows[i] or {kind='empty'} end
 p.entries[40]={kind='player',charName=h.name,class='warrior',role='tank'};p.plannerPlayerSlot=40;h.env.RefreshComposition();return p
end
local function footer(h)return assert(h.env.ShirsRaidBuilderMainFrame.priceText,'visible Hire price footer missing'):GetText() end
local function start(rows)
 local a,b,c,pump,open,emit,state=fixture();setPlan(a,rows or {normal('Alice'),normal('Bob')});return a,b,c,pump,open,emit,state
end
local function refresh(h)h:click(h.env.ShirsRaidBuilderMainFrame.syncButton) end
local function noActions(h)
 assert(not h.C.handAuthority and not h.C.handRunPlan,'refresh granted spending authority')
 for _,p in ipairs(h.history) do assert(not h.C.HandParse(p.text),'refresh sent hire handoff') end
end

test('registered Refresh waits for native synchronization and estimates every own and linked normal in board order',function()
 local a,b,c,pump=start({normal('Alice'),normal('Bob'),normal('Alice'),normal('Carol'),{kind='guest',charName='Human',class='priest',role='healer'},{kind='legacy',sourceName='Oldmage',charName='Oldmage',class='mage',role='rdps'}})
 a.counts.Alice=1;b.counts.Bob=2;local before=a.C.PlannerCopy(a:preset());refresh(a)
 assert(table.getn(a.quoteReads)==0 and table.getn(b.quoteReads)==0,'quote started before synchronization completion')
 assert(string.find(footer(a),'Synchronizing',1,true));pump(30)
 assert(string.find(footer(a),'Estimated total: 2g 60s',1,true),footer(a))
 assert(a.C.visiblePrice.estimate.known==4 and a.C.visiblePrice.estimate.unknown==0)
 assert(table.getn(a.quoteReads)==1 and table.getn(b.quoteReads)==1 and table.getn(c.quoteReads)==1,'duplicate quote or wrong owner')
 assert(a.C.PlannerEqual(before,a:preset()),'estimate changed saved profile');for _,h in ipairs({a,b,c}) do noActions(h) end
 local host=a.env.ShirsRaidBuilderMainFrame.priceFrame;assert(host.point[1]=='BOTTOMLEFT' and host.point[4]>=204 and host:GetWidth()<=550,'footer moved outside board bottom area')
end)

test('proposal and current-plan totals stay separate even when Composition asks for different rows',function()
 local a,b,c,pump,open=start({normal('Alice')});local p=open(a,{Bob=true},3);a:click(p.buildButton);pump(12)
 assert(p.proposal and p.proposal.normal==3);local preview=p.previewText:GetText();refresh(a);pump(30)
 assert(string.find(footer(a),'Estimated total: 90s',1,true),footer(a))
 assert(p.previewText:GetText()==preview and p.proposal.normal==3,'current-plan estimate rewrote proposal')
end)

test('double Refresh coalesces while pending and never recursively synchronizes or repeats quotes',function()
 local a,b,c,pump=start();local native=a.C.SyncRefreshAll;local calls=0;a.C.SyncRefreshAll=function()calls=calls+1;return native()end
 refresh(a);refresh(a);refresh(a);pump(30);assert(calls==1,'duplicate or recursive Refresh')
 assert(table.getn(a.quoteReads)==1 and table.getn(b.quoteReads)==1,'duplicate quote storm')
 local reads=table.getn(a.quoteReads)+table.getn(b.quoteReads);pump(60)
 assert(calls==1 and table.getn(a.quoteReads)+table.getn(b.quoteReads)==reads,'background requote loop')
 assert(string.find(footer(a),'unknown',1,true),'expired estimate remained current')
end)

test('profile edits race source tier count and account changes revoke sync and cannot price another profile',function()
 for _,mode in ipairs({'profile','replace','race','source','tier','rowcount','account','sourcecount','close','sort'}) do
  local a,b,c,pump=start();refresh(a);local p=a:preset();local old=a.C.PlannerCopy(p)
  if mode=='profile' then a.env.ShirsRaidBuilderDB.presets.Other={entries={normal('Carol')},denyRules={},setupRules={}};a.env.ShirsRaidBuilderDB.currentPreset='Other'
  elseif mode=='replace' then a.env.ShirsRaidBuilderDB.presets.Default=a.C.PlannerCopy(p)
  elseif mode=='race' then p.entries[1].race='human'
  elseif mode=='source' then p.entries[1].account='Carol'
  elseif mode=='tier' then p.entries[1].tier='t2d'
  elseif mode=='rowcount' then p.entries[3]=normal('Alice')
  elseif mode=='account' then a.env.ShirsRaidBuilderDB.syncAccountId=string.rep('9',16)
  elseif mode=='sourcecount' then a.env.ShirsRaidBuilderDB.inviteCharacters.Alice.count=3;a.env.ShirsRaidBuilderDB.inviteCharacters.Alice.maxCount=4
  elseif mode=='close' then a.env.ShirsRaidBuilderMainFrame:Hide()
  else a.env.ShirsRaidBuilderDB.uiMode='sort' end
  pump(35)
  assert(not a.C.visiblePrice or a.C.visiblePrice.phase~='done' or not a.C.visiblePrice.estimate.complete,mode..' accepted stale work')
  assert(not a.C.plannerQuotes and table.getn(a.quoteReads)==0 and table.getn(b.quoteReads)==0,mode..' retained continuation')
  if mode~='profile' and mode~='sort' and mode~='close' then assert(string.find(footer(a),'unknown',1,true),mode..' footer stale') end
  noActions(a)
 end
end)

test('Stop cancels a pending linked quote and a late response cannot restore its total',function()
 local a,b,c,pump,open,emit=start();b.noReply=true;refresh(a)
 for i=1,160 do pump(0.25);if b.C.plannerQuoteFlight then break end end
 assert(b.C.plannerQuoteFlight,'fixture never started linked quote');a:click(a.env.ShirsRaidBuilderMainFrame.stopBtn);pump(1)
 emit(b,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE Bob:1000:1000:0:0:1000:1000:0:4','nexus');pump(4)
 assert(not a.C.plannerQuotes and string.find(footer(a),'unknown',1,true),'late quote replaced cancellation')
 assert(not a.C.visiblePrice or a.C.visiblePrice.phase~='done');noActions(a)
end)

test('unsupported peer and server timeout show an explicit partial subtotal, never a false full total',function()
 for _,mode in ipairs({'unsupported','timeout'}) do
  local a,b,c,pump=start();if mode=='unsupported' then b.C.QuoteEvent=function()end else b.noReply=true end
  refresh(a)
  for i=1,260 do pump(0.25);if a.C.visiblePrice and a.C.visiblePrice.phase=='done' then break end end
  local text=footer(a)
  assert(string.find(text,'Estimated total: unknown',1,true) and string.find(text,'subtotal',1,true),mode..': '..text)
  assert(not string.find(text,'Estimated total: 90s',1,true),'subtotal presented as full total')
  assert(a.C.visiblePrice.estimate.known==1 and a.C.visiblePrice.estimate.unknown==1);noActions(a)
 end
end)

test('unknown or untrusted source remains unknown while supported own rows still get a subtotal',function()
 local a,b,c,pump=start({normal('Alice'),normal('Missing')});refresh(a);pump(30)
 assert(string.find(footer(a),'Estimated total: unknown',1,true) and a.C.visiblePrice.estimate.known==1 and a.C.visiblePrice.estimate.unknown==1,footer(a))
 assert(table.getn(a.quoteReads)==1 and table.getn(b.quoteReads)==0);noActions(a)
end)

test('human and legacy-only plans need no quote and return a genuine zero normal-hire estimate',function()
 local a,b,c,pump=start({{kind='legacy',sourceName='Oldmage',charName='Oldmage',class='mage',role='rdps'}});refresh(a);pump(30)
 assert(string.find(footer(a),'Estimated total: 0c',1,true));assert(table.getn(a.quoteReads)==0 and table.getn(b.quoteReads)==0 and a.C.visiblePrice.estimate.unknown==0)
end)

test('a finished estimate is invalidated by changed source capacity and does not auto-request again',function()
 local a,b,c,pump=start({normal('Alice')});refresh(a);pump(25);assert(string.find(footer(a),'Estimated total: 90s',1,true))
 a.env.ShirsRaidBuilderDB.inviteCharacters.Alice.count=2;a.env.ShirsRaidBuilderDB.inviteCharacters.Alice.maxCount=4;pump(0.25)
 assert(string.find(footer(a),'unknown',1,true) and table.getn(a.quoteReads)==1,'source count change retained current total or triggered quote')
end)

print("Shir's Raid Builder visible plan prices tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'visible plan price regressions failed')
