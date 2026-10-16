-- Additional visible-profile consumers of the unchanged trusted quote protocol.
local f=assert(io.open('test_visible_plan_prices.lua'));local src=f:read('*a');f:close()
local at=assert(string.find(src,"\ntest('registered Refresh",1,true));local start,normal,setPlan,footer,refresh,noActions=assert(loadstring(string.sub(src,1,at-1)..'\nreturn start,normal,setPlan,footer,refresh,noActions'))()
local pass,fail=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..n) else fail=fail+1;print('FAIL '..n..': '..tostring(e)) end end
local function finished(a,pump)
 for i=1,280 do pump(0.25);if a.C.visiblePrice and a.C.visiblePrice.phase=='done' then return a.C.visiblePrice end end
 error('price check never settled: '..footer(a))
end

test('actual mixed-licence own and linked quotes retain race masks and true Random across character ordinals',function()
 local random={kind='normal',account='Alice',tier='t3r',class='random',role='dps'}
 local a,b,c,pump,open,emit=start({normal('Alice','t3r','gnome'),normal('Bob','t3r','human'),normal('Alice','t2d','human'),random,normal('Alina','t1r','gnome')})
 a.prices.Alina=750;a.noReply=true;b.noReply=true
 a.env.ShirsRaidBuilderDB.inviteCharacters.Alina={name='Alina',level=60,dungeonLicense='t2d',raidLicense='t1r',faction='Alliance'}
 a.roster='Alice:warrior:t2d:t3r:A:0:60:0:4 Alina:mage:t2d:t1r:A:0:60:0:4'
 local before=a.C.PlannerCopy(a:preset());refresh(a)
 for i=1,240 do
  pump(0.25)
  for _,h in ipairs({a,b}) do local flight=h.C.plannerQuoteFlight
   if flight and not flight.drain then
    local base,ex,mask,qbase,qex,count=9000,900,'7',12000,1200,1
    if h==b then base,ex,mask,qbase,qex,count=5000,500,'1',6000,600,2
    elseif flight.source.name=='Alina' then base,ex,mask,qbase,qex,count=750,75,'1',1000,100,0
    elseif flight.tier=='t2d' then base,ex,mask,qbase,qex=3000,300,'1',4000,400 end
    emit(h,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE '..flight.source.name..':'..base..':'..ex..':'..mask..':17:'..qbase..':'..qex..':'..count..':4','nexus')
   end
  end
  if a.C.visiblePrice and a.C.visiblePrice.phase=='done' then break end
 end
 local w=assert(a.C.visiblePrice);assert(w.estimate and w.estimate.complete and w.estimate.totalCopper==42650,footer(a))
 assert(table.getn(a.quoteReads)==3 and table.getn(b.quoteReads)==1,'not exactly one request per actual source/licence')
 assert(a.C.PlannerEqual(before,a:preset()) and a:preset().entries[4].class=='random' and not a:preset().entries[4].race,'Random outcome invented')
 assert(w.quotes['own:alice:t3r'].mask=='7' and w.quotes['own:alice:t2d'].mask=='1','licence contexts crossed');noActions(a);noActions(b)
end)

test('offline and untrusted linked sources never borrow own discounts or gain trust',function()
 for _,mode in ipairs({'offline','untrusted'}) do
  local a,b,c,pump=start();if mode=='offline' then b.env.SendChatMessage=function()end else a.env.ShirsRaidBuilderDB.peerLinks={} end
  local trust=a.C.PlannerCopy(a.env.ShirsRaidBuilderDB.peerLinks);refresh(a);local w=finished(a,pump)
  assert(not w.estimate.complete and w.estimate.known==1 and w.estimate.unknown==1 and w.estimate.totalCopper==9000,mode..': '..footer(a))
  assert(a.C.PlannerEqual(trust,a.env.ShirsRaidBuilderDB.peerLinks),'quote added trust');assert(table.getn(b.quoteReads)==0,'offline/untrusted peer got a quote');noActions(a)
 end
end)

test('late local quote drains before another licence request can begin',function()
 local a,b,c,pump,open,emit=start({normal('Alice')});a.noReply=true;refresh(a)
 for i=1,160 do pump(0.25);if a.C.plannerQuoteFlight then break end end
 assert(a.C.plannerQuoteFlight,'no local flight');a:preset().entries[1].tier='t2d';a.env.RefreshComposition()
 assert(a.C.plannerQuoteFlight.drain and not a.C.plannerQuotes,'edit failed to retain drain sentinel')
 refresh(a);finished(a,pump);assert(table.getn(a.quoteReads)==1,'new licence sent before old reply drained')
 emit(a,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE Alice:9000:9000:0:0:9000:9000:0:4','nexus');pump(1)
 assert(not a.C.plannerQuoteFlight and string.find(footer(a),'unknown',1,true),'drained quote became current')
 a.noReply=false;refresh(a);local w=finished(a,pump);assert(w.estimate.complete and table.getn(a.quoteReads)==2 and a.quoteReads[2].tier=='t2d',footer(a));noActions(a)
end)

test('real profile selector away and back cannot revive an old quote',function()
 local a,b,c,pump=start();a.env.ShirsRaidBuilderDB.presets.Other={entries={normal('Carol')},denyRules={},setupRules={}}
 refresh(a);local main=a.env.ShirsRaidBuilderMainFrame;local selector=a:button(main,'Default');selector.options={'Default','Other'}
 a:choose(selector,'Other');a:choose(selector,'Default');pump(35)
 assert(not a.C.visiblePrice and not a.C.plannerQuotes and table.getn(a.quoteReads)==0,'profile return revived continuation');noActions(a)
end)

test('MCP Invite conflict is fenced and never changes MCP character or licence globals',function()
 local a,b,c,pump,open,emit=start({normal('Alice')});a.noReply=true;refresh(a)
 for i=1,160 do pump(0.25);if a.C.plannerQuoteFlight then break end end
 assert(a.C.plannerQuoteFlight);a.env.MCP_InviteName='Other';a.env.MCP_InviteLicenses={'t2d'};a.env.MCP_InviteLicItr=1
 a.env.MCPInviteFrame=a.env.CreateFrame('Frame');pump(0.25);assert(a.C.quoteUnsafeMCP and not a.C.plannerQuotes,'MCP overlap not fenced')
 emit(a,'CHAT_MSG_ADDON','[nexus] ACINFO:COST:INVITE Alice:9000:9000:0:0:9000:9000:0:4','nexus');a.env.MCPInviteFrame:Hide();pump(1)
 refresh(a);finished(a,pump);assert(table.getn(a.quoteReads)==1 and string.find(footer(a),'unknown',1,true),'reload fence bypassed')
 assert(a.env.MCP_InviteName=='Other' and a.env.MCP_InviteLicenses[1]=='t2d' and a.env.MCP_InviteLicItr==1,'MCP UI state hijacked');noActions(a)
end)

test('registered group/world event cancels waiting synchronization and cannot continue later',function()
 for _,ev in ipairs({'RAID_ROSTER_UPDATE','PARTY_MEMBERS_CHANGED','PLAYER_LEAVING_WORLD'}) do
  local a,b,c,pump,open,emit=start();refresh(a);emit(a,ev);pump(35)
  assert(not a.C.visiblePrice and not a.C.plannerQuotes and table.getn(a.quoteReads)==0 and table.getn(b.quoteReads)==0,ev..' retained continuation');noActions(a)
 end
end)

test('completed estimate never survives reload as a current price and opening remains display-only',function()
 local a,b,c,pump,open=start({normal('Alice')});refresh(a);assert(finished(a,pump).estimate.complete)
 local f=assert(io.open('test_individual_editor.lua'));local s=f:read('*a');f:close();local at=assert(string.find(s,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(s,1,at-1)..'\nreturn boot'))()
 local re=boot(a.C.PlannerCopy(a.env.ShirsRaidBuilderDB),'Alice');assert(not re.C.visiblePrice and string.find(footer(re),'unknown',1,true),'saved price restored as fresh')
 assert(not re.C.plannerQuotes and not re.C.plannerQuoteFlight,'open initiated a price request')
end)

print("Shir's Raid Builder visible price safety tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)');assert(fail==0,'visible safety regressions failed')
