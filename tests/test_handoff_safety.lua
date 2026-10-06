dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local p={entries={{kind='normal',account='Alice',class='mage',role='rdps',race='human',gender='female',tier='t2r',spec='frost'}}}
local h=assert(C.HandCreate(p,'Safety','Alice','FixtureRealm',{'Alice'},'1234567890123456',1800000000))
local s=C.PeerNew('Alice','Bob','FixtureRealm'); s.handOut={'queued'}; s.handInput={}; s.handProposal={}
C.PeerClear(s,'revoked')
assert(not s.handOut and not s.handInput and not s.handProposal,'revocation retains handoff data')
assert(not C.HandCreate(p,'Safety','Alice','FixtureRealm',{},'1234567890123456',1800000000),'missing actor accepted')
local wrong={entries={{kind='normal',account='Bob',class='mage',role='rdps'}}}
assert(not C.HandCreate(wrong,'Safety','Alice','FixtureRealm',{'Alice'},'1234567890123456',1800000000),'foreign normal hire accepted')
assert(not C.HandScope(p.entries,{{name='Foreign',owner='Bob',class='mage',role='rdps'}},'Alice'),'foreign normal targets')
local legacy={{kind='legacy',charName='Legacy',class='mage',role='rdps'}}
assert(not C.HandScope(legacy,{{name=C.GetLegacyWhisperName(legacy[1]),owner='Bob',class='mage',role='rdps'}},'Alice'),'foreign legacy target accepted')
assert(not C.HandScope(legacy,{},'Alice'),'missing legacy silently skipped')
assert(table.getn(assert(C.HandScope(p.entries,{{name='Local',owner='Alice',class='mage',role='rdps'}},'Alice')))==1)
assert(not C.HandRestore({phase='running',steps=false},'Alice','FixtureRealm',1800000000),'malformed restore accepted')
local named={kind='normal',account='Alice',companionName='Named',class='mage',role='rdps'}
assert(not C.NormalHireMatchesInfo(named,{name='Named',owner='Bob',class='mage',role='rdps'}),'named hire ignores owner')
assert(table.getn(assert(C.HandScope(legacy,{},'Alice',{[C.GetLegacyWhisperName(legacy[1])]=true})))==1,'roster-backed legacy fallback lost')
-- A leader waiting on a granted group advances once, only on a REPORT for that exact
-- run, revision, account claims and step from that group's actor.
local bobRow={kind='normal',account='Bob',class='mage',role='rdps',race='human',gender='female',tier='t2r',spec='frost'}
local two={entries={[1]={kind='legacy',charName='First',class='mage',role='rdps'},[6]=bobRow}}
local lead=assert(C.HandCreate(two,'Safety','Alice','FixtureRealm',{'Alice','Bob'},'1234567890123458',1800000000))
lead.kind='GRANT'; lead.accounts={'1111111111111111','2222222222222222'}; lead.expires=1800007200; lead.step=2; lead.phase='waiting'
local function report(edit)
 local r=assert(C.HandDecode(C.HandEncode(lead))); r.kind='REPORT'
 if edit then edit(r) end
 return r
end
assert(not C.HandReport(lead,report(function(r) r.step=1 end),'Bob','Alice','FixtureRealm',1800000001),'stale step REPORT advanced')
assert(not C.HandReport(lead,report(function(r) r.plan.entries[1].charName='Other' end),'Bob','Alice','FixtureRealm',1800000001),'wrong revision REPORT advanced')
assert(not C.HandReport(lead,report(function(r) r.accounts[2]='3333333333333333' end),'Bob','Alice','FixtureRealm',1800000001),'wrong account REPORT advanced')
assert(not C.HandReport(lead,report(function(r) r.id='1234567890123459' end),'Bob','Alice','FixtureRealm',1800000001),'other run REPORT advanced')
assert(not C.HandReport(lead,report(),'Carol','Alice','FixtureRealm',1800000001),'wrong sender REPORT advanced')
assert(not C.HandReport(lead,report(),'Bob','Alice','FixtureRealm',1800007200),'expired REPORT advanced')
assert(lead.step==2 and lead.phase=='waiting','rejected REPORTs moved the run')
assert(C.HandReport(lead,report(),'Bob','Alice','FixtureRealm',1800000001) and lead.phase=='done','exact REPORT refused')
assert(not C.HandReport(lead,report(),'Bob','Alice','FixtureRealm',1800000002),'duplicate REPORT advanced')
-- An authorized H6 GRANT may assign the first occupied group to a linked account; the
-- initiator stays origin and account claims stay per group. The plain H5 form of such a
-- run is never valid, standalone or executable, so chained H5 keeps its step>=2 rule.
local first={entries={[1]=bobRow,[6]={kind='legacy',charName='Third',class='mage',role='rdps'},[7]={kind='player',charName='Alice',class='warrior',role='tank'}}}
local function firstRun(kind)
 local run={id='1234567890123457',origin='Alice',realm='FixtureRealm',expires=1800007200,step=1,name='Safety',
  plan=assert(C.PlanDecode(C.PlanEncode(first,'hire','Safety'))),steps={{group=1,actor='Bob'},{group=2,actor='Alice'}}}
 if kind then run.kind=kind; run.accounts={'2222222222222222','1111111111111111'} end
 return run
end
local plain=firstRun()
assert(not C.HandEncode(plain),'plain H5 accepted a first actor other than its origin')
assert(not C.HandApprove({},plain,'Alice','Bob','FixtureRealm',1800000001),'plain H5 step 1 approved')
local wire=assert(C.HandEncode(firstRun('GRANT')),'authorized first-remote GRANT not encodable')
local got=assert(C.HandDecode(wire),'first-remote GRANT not decodable')
assert(C.HandEncode(got)==wire and got.kind=='GRANT' and got.origin=='Alice' and got.step==1 and got.steps[1].actor=='Bob'
 and got.steps[2].actor=='Alice' and got.accounts[1]=='2222222222222222' and got.accounts[2]=='1111111111111111','first-remote GRANT not canonical')
local _,_,base=string.find(wire,'^H6~GRANT~[0-9,]+~(H5~.+)$')
assert(base and not C.HandDecode(base),'first-remote run decodes as plain H5')
assert(C.HandGrantBound(got,'Alice','Bob','2222222222222222','1111111111111111'),'bound first-remote GRANT refused')
assert(not C.HandGrantBound(got,'Alice','Bob','3333333333333333','1111111111111111'),'first-remote GRANT ignored receiver account')
assert(not C.HandGrantBound(got,'Alice','Bob','2222222222222222','3333333333333333'),'first-remote GRANT ignored leader account')
assert(not C.HandGrantBound(got,'Carol','Bob','2222222222222222','1111111111111111'),'first-remote GRANT accepted a non-origin sender')
assert(not C.HandApprove({},got,'Carol','Bob','FixtureRealm',1800000001),'first-remote GRANT approved from a non-origin sender')
assert(not C.HandApprove({},got,'Alice','Carol','FixtureRealm',1800000001),'first-remote GRANT approved for another actor')
assert(not C.HandApprove({},got,'Alice','Bob','OtherRealm',1800000001),'first-remote GRANT approved on another realm')
assert(not C.HandApprove({},got,'Alice','Bob','FixtureRealm',1800007200),'expired first-remote GRANT approved')
local asReport=assert(C.HandDecode(wire)); asReport.kind='REPORT'
assert(not C.HandApprove({},asReport,'Alice','Bob','FixtureRealm',1800000001),'step 1 REPORT approved as work')
local store={}
assert(C.HandApprove(store,got,'Alice','Bob','FixtureRealm',1800000001) and store.active.phase=='ready' and store.active.step==1,'authorized step 1 GRANT refused')
assert(not C.HandApprove(store,assert(C.HandDecode(wire)),'Alice','Bob','FixtureRealm',1800000002),'replayed step 1 GRANT approved')
local q=assert(C.HandStepPlan(store.active,{},'Bob'),'granted first group not runnable by its actor')
assert(q.entries[1].account=='Bob' and not q.entries[6] and not q.entries[7],'first-remote step leaked other groups')
assert(not C.HandStepPlan(store.active,{},'Alice'),'leader can run the remote first group')
-- Hire-from source resolution: only current, same-realm, linked account snapshots map a
-- character to a linked endpoint; unclear ownership refuses; the row's account never changes.
local B,Cid='2222222222222222','3333333333333333'
local function linkTo(links,peer,realm)
 local e=C.PeerNew('Alice',peer,realm or 'FixtureRealm'); e.phase='linked'; assert(C.LinkSave(links,e,true))
end
local function claim(links,peer,id,names,realm)
 realm=realm or 'FixtureRealm'
 local seen=1799999400; local rows={}
 for _,name in ipairs(names) do table.insert(rows,{name=name,level=60,dungeonLicense='t1d',raidLicense='t2r',observed=seen}) end
 return assert(C.AccountSavedCopy({accountId=id,source=string.lower(peer),realm=realm,received=seen,observed=seen,entries=rows,authoritative=false},'Alice',realm,links))
end
local function row(account) local r={}; for k,v in pairs(bobRow) do r[k]=v end; r.account=account; return r end
local links={}; linkTo(links,'Bob')
local licenses={['FixtureRealm;bob']=claim(links,'Bob',B,{'Bob','Bobalt'})}
local src=C.HandRemoteSources(licenses,links,'Alice','FixtureRealm')
assert(src.bob.endpoint=='Bob' and src.bob.accountId==B and src.bobalt.endpoint=='Bob' and src.bobalt.accountId==B,'trusted linked alt not resolved')
local board={entries={[1]={kind='legacy',charName='First',class='mage',role='rdps'},[6]=row('Bobalt')}}
local actors,remote=C.HandActors(board,'Alice',{alice=true},src)
assert(actors[1]=='Alice' and actors[2]=='Bob' and remote,'linked alt group not assigned to its endpoint')
local run=assert(C.HandCreate(board,'Safety','Alice','FixtureRealm',actors,'1234567890123460',1800000000,{alice=true},src),'resolved linked alt refused')
assert(run.steps[2].actor=='Bob' and run.plan.entries[6].account=='Bobalt' and board.entries[6].account=='Bobalt','hire-from source rewritten')
assert(not C.HandCreate(board,'Safety','Alice','FixtureRealm',actors,'1234567890123460',1800000000,{alice=true}),'linked alt accepted without source evidence')
assert(C.HandOwnsSource('Bobalt','Bob','Alice',nil,src) and not C.HandOwnsSource('Bobalt','Carol','Alice',nil,src)
 and not C.HandOwnsSource('Zed','Bob','Alice',nil,src),'source evidence mapped to the wrong endpoint')
-- Own and remote claims on one character refuse visibly before any command.
assert(not C.HandOwnsSource('Bobalt','Bob','Alice',{bobalt=true},src),'own+remote source accepted')
local none,_,group,unclear=C.HandActors(board,'Alice',{alice=true,bobalt=true},src)
assert(not none and group==2 and unclear=='Bobalt','own+remote ownership not refused')
-- Only a literal true own entry moves a foreign hire-from name onto this client.
assert(not C.HandOwnsSource('Bob','Alice','Alice',{bob=1}) and not C.HandOwnsSource('Bob','Alice','Alice',{bob='yes'}),'truthy own evidence accepted')
assert(C.HandOwnsSource('Bob','Alice','Alice',{bob=true}),'literal own evidence refused')
assert(not C.HandCreate(wrong,'Safety','Alice','FixtureRealm',{'Alice'},'1234567890123461',1800000000,{bob=1}),'foreign normal hire accepted on truthy own evidence')
actors=C.HandActors(board,'Alice',{alice=true,bobalt='yes'},{})
assert(actors[2]=='Bobalt','truthy own evidence claimed a foreign character')
-- A mapping keyed under another source is untrusted and ignored.
assert(C.HandRemoteSources({['FixtureRealm;mallory']=licenses['FixtureRealm;bob']},links,'Alice','FixtureRealm').bobalt==nil,'mis-keyed snapshot trusted')
-- Another realm's linked snapshot never maps characters on this realm.
linkTo(links,'Carol','OtherRealm')
local far=C.HandRemoteSources({['OtherRealm;carol']=claim(links,'Carol',Cid,{'Carol','Faralt'},'OtherRealm')},links,'Alice','FixtureRealm')
assert(far.faralt==nil and far.carol==nil,'other realm snapshot mapped here')
-- The same character claimed by two different accounts is ambiguous.
linkTo(links,'Carol')
local split=C.HandRemoteSources({['FixtureRealm;bob']=claim(links,'Bob',B,{'Bob','Shared'}),
 ['FixtureRealm;carol']=claim(links,'Carol',Cid,{'Carol','Shared'})},links,'Alice','FixtureRealm')
assert(split.shared==false and split.bob.endpoint=='Bob' and split.carol.endpoint=='Carol','cross-account claim not ambiguous')
none,_,group,unclear=C.HandActors({entries={[1]=row('Shared')}},'Alice',{alice=true},split)
assert(not none and group==1 and unclear=='Shared','cross-account claim routed')
-- Several endpoints of one account: an exact endpoint name wins; otherwise refuse.
linkTo(links,'Bobby')
local pair=C.HandRemoteSources({['FixtureRealm;bob']=claim(links,'Bob',B,{'Bob','Bobby','Bobalt'}),
 ['FixtureRealm;bobby']=claim(links,'Bobby',B,{'Bob','Bobby','Bobalt'})},links,'Alice','FixtureRealm')
assert(pair.bob.endpoint=='Bob' and pair.bobby.endpoint=='Bobby' and pair.bobalt==false,'same-account endpoints not deterministic')
none,_,group,unclear=C.HandActors({entries={[1]={kind='legacy',charName='First',class='mage',role='rdps'},[6]=row('Bobalt')}},'Alice',{alice=true},pair)
assert(not none and group==2 and unclear=='Bobalt','same-account alt routed without an exact endpoint')
-- Live evidence narrows one account's endpoints only: the single endpoint with a live
-- trusted session whose account claim arrived in that session, matches and lists the
-- name. A saved snapshot alone is never live evidence; anything less keeps the rule above.
local pairClaims={['FixtureRealm;bob']=claim(links,'Bob',B,{'Bob','Bobby','Bobalt'}),['FixtureRealm;bobby']=claim(links,'Bobby',B,{'Bob','Bobby','Bobalt'})}
local function session(peer,id,names,edit)
 local s=C.PeerNew('Alice',peer,'FixtureRealm'); s.phase='linked'; s.a='100001'; s.b='100002'; s.started=100; s.deadline=160; s.expires=1800000060
 local rows={}
 for _,name in ipairs(names) do table.insert(rows,{name=name,level=60,dungeonLicense='t1d',raidLicense='t2r',observed=1800000000}) end
 s.remoteLicense={source=string.lower(peer),realm='FixtureRealm',accountId=id,entries=rows,received=1800000000,observed=1800000000,authoritative=false}
 if edit then edit(s) end
 return {state=s}
end
local all={'Bob','Bobby','Bobalt'}
local function routed(sessions,wall,clock,at) return C.HandRemoteSources(pairClaims,at or links,'Alice','FixtureRealm',sessions,wall or 1800000001,clock or 101) end
local live=routed({session('Bob',B,all)})
assert(live.bobby.endpoint=='Bob' and live.bobalt.endpoint=='Bob' and live.bob.endpoint=='Bob' and live.bobby.accountId==B,'live endpoint did not take its account names')
local liveBoard={entries={[1]=row('Bobby'),[6]=row('Bobalt')}}
local liveRun=assert(C.HandCreate(liveBoard,'Safety','Alice','FixtureRealm',C.HandActors(liveBoard,'Alice',{alice=true},live),'1234567890123465',1800000000,{alice=true},live,true),
 'live routing refused by the frozen-run checks')
assert(liveRun.steps[1].actor=='Bob' and liveRun.steps[2].actor=='Bob' and liveRun.plan.entries[1].account=='Bobby' and liveRun.plan.entries[6].account=='Bobalt',
 'live routing changed a hire-from source')
local function kept(r,why) assert(r.bobby.endpoint=='Bobby' and r.bobalt==false and r.bob.endpoint=='Bob',why..' changed saved routing') end
kept(C.HandRemoteSources(pairClaims,links,'Alice','FixtureRealm'),'no sessions')
kept(routed({}),'no live session')
kept(C.HandRemoteSources(pairClaims,links,'Alice','FixtureRealm',{session('Bob',B,all)}),'no clock')
kept(routed({session('Bob',B,all)},1800000060),'wall-expired session')
kept(routed({session('Bob',B,all)},nil,160),'clock-expired session')
kept(routed({session('Bob',B,all,function(s) s.realm='OtherRealm' end)}),'other-realm session')
kept(routed({session('Bob',B,all,function(s) s.phase='waiting' end)}),'handshake not linked')
kept(routed({session('Bob',B,all,function(s) s.you='carol' end)}),'session of another local character')
kept(routed({session('Bob',Cid,all)}),'account claim mismatch')
kept(routed({session('Bob',B,all,function(s) s.remoteLicense=nil end)}),'saved snapshot only')
kept(routed({session('Bob',B,all,function(s) s.remoteLicense.accountId=nil end)}),'license rows without an account claim')
kept(routed({session('Bob',B,all,function(s) s.remoteLicense.source='bobby' end)}),'claim from another endpoint')
local unlinked={}; linkTo(unlinked,'Bobby')
local revokedLive=routed({session('Bob',B,all)},nil,nil,unlinked)
assert(revokedLive.bobby.endpoint=='Bobby' and revokedLive.bobalt.endpoint=='Bobby' and revokedLive.bob.endpoint=='Bobby','unlinked live session routed work')
-- Any character of an account hires from any other, and one account is online on one
-- character at a time: a live endpoint takes every name its account lists, even one its
-- fresh claim omits. The receiver still refuses a name its own rows do not list.
local partial=routed({session('Bob',B,{'Bob','Bobalt'})})
assert(partial.bobby.endpoint=='Bob' and partial.bobalt.endpoint=='Bob','live endpoint did not take a name its account lists')
-- Without a live session, the account's current character is the endpoint whose snapshot
-- arrived last; on a tie each endpoint keeps its own name (the rule above).
local function claimAt(peer,names,at)
 local copy=claim(links,peer,B,names)
 copy.received=at; copy.observed=at
 for _,e in ipairs(copy.entries) do e.observed=at end
 return copy
end
local function newest(bobAt,bobbyAt,sessions)
 return C.HandRemoteSources({['FixtureRealm;bob']=claimAt('Bob',all,bobAt),['FixtureRealm;bobby']=claimAt('Bobby',all,bobbyAt)},
  links,'Alice','FixtureRealm',sessions,1800000001,101)
end
local late=newest(1799999400,1799900000)
assert(late.bob.endpoint=='Bob' and late.bobby.endpoint=='Bob' and late.bobalt.endpoint=='Bob','newest snapshot did not take its account names')
late=newest(1799900000,1799999400)
assert(late.bob.endpoint=='Bobby' and late.bobby.endpoint=='Bobby' and late.bobalt.endpoint=='Bobby','newest snapshot order not followed')
late=newest(1799900000,1799999400,{session('Bob',B,all)})
assert(late.bobby.endpoint=='Bob' and late.bobalt.endpoint=='Bob','live session did not outrank a newer saved snapshot')
late=newest(1799999400,1799900000,{session('Bob',B,all),session('Bobby',B,all)})
assert(late.bob.endpoint=='Bob' and late.bobby.endpoint=='Bobby' and late.bobalt==false,'two live endpoints routed by snapshot age')
assert(late.bobby.accountId==B,'endpoint lost its account claim')
-- Two live endpoints of one account: each keeps its own name; a third name stays ambiguous.
local both=routed({session('Bob',B,all),session('Bobby',B,all)})
assert(both.bobby.endpoint=='Bobby' and both.bob.endpoint=='Bob' and both.bobalt==false,'two live endpoints routed an ambiguous name')
-- Cross-account ambiguity stays closed whatever is live.
local cross=C.HandRemoteSources({['FixtureRealm;bob']=claim(links,'Bob',B,{'Bob','Shared'}),['FixtureRealm;carol']=claim(links,'Carol',Cid,{'Carol','Shared'})},
 links,'Alice','FixtureRealm',{session('Bob',B,{'Bob','Shared'})},1800000001,101)
assert(cross.shared==false,'live endpoint opened a cross-account ambiguity')
-- Revoking the character link removes its snapshot mapping, even if still loaded.
C.LinkForget(links,'Alice','Bob','FixtureRealm',false)
assert(not C.LinkKnown(links,'Alice','Bob','FixtureRealm'),'fixture revoke failed')
local revoked=C.HandRemoteSources(licenses,links,'Alice','FixtureRealm')
assert(revoked.bob==nil and revoked.bobalt==nil,'revoked link still maps characters')
actors=C.HandActors(board,'Alice',{alice=true},revoked)
assert(actors[2]=='Bobalt' and not C.HandCreate(board,'Safety','Alice','FixtureRealm',{'Alice','Bob'},'1234567890123462',1800000000,{alice=true},revoked),
 'revoked mapping still routes Bobalt to Bob')
-- Several accounts in one raid group: an authorized run splits it into exact slot chunks
-- in board order, covering every occupied slot once. Plain H5 never carries chunks, and
-- earlier versions only parse two-field step rows, so they reject chunk rows outright.
local A='1111111111111111'
local chunkLinks={}; linkTo(chunkLinks,'Bob')
local chunkSrc=C.HandRemoteSources({['FixtureRealm;bob']=claim(chunkLinks,'Bob',B,{'Bob','Bobalt','Bobina'})},chunkLinks,'Alice','FixtureRealm')
local mine={alice=true,alicia=true,aliana=true}
local function legacyRow(name) return {kind='legacy',charName=name,class='mage',role='rdps'} end
local mixedBoard={entries={[1]=legacyRow('First'),[6]=row('Alicia'),[7]=legacyRow('Seventh'),[8]=row('Bobalt'),[11]=legacyRow('Third')}}
local slots,splitRemote=C.HandActors(mixedBoard,'Alice',mine,chunkSrc)
assert(splitRemote and slots[1]=='Alice' and slots[3]=='Alice' and type(slots[2])=='table' and slots[2][6]=='Alice'
 and slots[2][7]=='Alice' and slots[2][8]=='Bob','mixed group slots not mapped to their actors')
local lead2=C.HandActors({entries={[6]=legacyRow('Lead'),[7]=row('Bobalt'),[8]=row('Alicia')}},'Alice',mine,chunkSrc)
assert(lead2[2][6]=='Bob' and lead2[2][7]=='Bob' and lead2[2][8]=='Alice','leading legacy row did not join the first actor')
assert(not C.HandCreate(mixedBoard,'Safety','Alice','FixtureRealm',slots,'1234567890123463',1800000000,mine,chunkSrc),'plain H5 split a group')
local chunked=assert(C.HandCreate(mixedBoard,'Safety','Alice','FixtureRealm',slots,'1234567890123463',1800000000,mine,chunkSrc,true),'authorized mixed group refused')
local shape={}; for _,s in ipairs(chunked.steps) do table.insert(shape,s.group..'='..s.actor..(s.first and ('@'..s.first..'-'..s.last) or '')) end
assert(table.concat(shape,',')=='1=Alice,2=Alice@6-7,2=Bob@8-8,3=Alice','mixed group chunks: '..table.concat(shape,','))
chunked.kind='GRANT'; chunked.accounts={A,A,B,A}; chunked.expires=1800007200
local chunkWire=assert(C.HandEncode(chunked),'chunked GRANT not encodable')
assert(string.find(chunkWire,'~1,Alice/2,Alice,6,7/2,Bob,8,8/3,Alice~',1,true),'chunk rows missing from the wire: '..chunkWire)
local _,_,chunkBase=string.find(chunkWire,'^H6~GRANT~[0-9,]+~(H5~.+)$')
assert(chunkBase and not C.HandDecode(chunkBase),'chunked base decodes as plain H5')
local back=assert(C.HandDecode(chunkWire),'chunked GRANT not decodable')
assert(C.HandEncode(back)==chunkWire and back.steps[2].first==6 and back.steps[2].last==7 and back.steps[3].first==8 and back.steps[3].last==8
 and C.HandRunScope(back)==C.HandRunScope(chunked),'chunked GRANT not canonical')
-- Malformed chunk runs never encode: overlapping, omitted, extraneous, reordered, lone,
-- same-actor, cross-group or mixed-shape chunks, backwards groups, or chunks outside a
-- GRANT/REPORT/PAUSE wrapper (plain H5 or END).
local function tampered(edit) local t=assert(C.HandDecode(chunkWire)); edit(t); return C.HandEncode(t) end
local malformed={
 overlap=function(t) t.steps[3].first=7 end,
 omitted=function(t) t.steps[2].last=6 end,
 extraneous=function(t) t.steps[3].last=9 end,
 reordered=function(t) t.steps[2],t.steps[3]=t.steps[3],t.steps[2] end,
 lone=function(t) t.steps[2].last=8; table.remove(t.steps,3); table.remove(t.accounts,3) end,
 sameActor=function(t) t.steps[3].actor='Alice' end,
 crossGroup=function(t) t.steps[3].first=11; t.steps[3].last=11 end,
 wholeAndChunk=function(t) t.steps[2].first=nil; t.steps[2].last=nil end,
 backwards=function(t) local last=table.remove(t.steps,4); table.insert(t.steps,2,last) end,
 plain=function(t) t.kind=nil; t.accounts=nil end,
 ended=function(t) t.kind='END' end}
for name,edit in pairs(malformed) do assert(not tampered(edit),'malformed chunk run accepted: '..name) end
local function swap(text,from,to)
 local at=string.find(text,from,1,true)
 return at and string.sub(text,1,at-1)..to..string.sub(text,at+string.len(from)) or text
end
for _,bad in ipairs({{',8,8/',',08,8/'},{'2,Bob,8,8','2,Bob,8'},{'2,Bob,8,8','2,Bob,8,8,8'}}) do
 local wire=swap(chunkWire,bad[1],bad[2])
 assert(wire~=chunkWire and not C.HandDecode(wire),'malformed chunk wire decoded: '..bad[2])
end
-- The run scope freezes chunk membership; a granted chunk runs exactly its own slots.
local moved=assert(C.HandDecode(chunkWire)); moved.steps[2].last=6; moved.steps[3].first=7
assert(C.HandEncode(moved) and C.HandRunScope(moved)~=C.HandRunScope(chunked),'chunk membership not bound to the run scope')
local waiting=assert(C.HandDecode(chunkWire)); waiting.step=3; waiting.phase='waiting'
local other=assert(C.HandDecode(assert(C.HandEncode(moved)))); other.kind='REPORT'; other.step=3
assert(not C.HandReport(waiting,other,'Bob','Alice','FixtureRealm',1800000001),'REPORT with other chunk membership advanced')
local exact=assert(C.HandDecode(chunkWire)); exact.kind='REPORT'; exact.step=3
assert(C.HandReport(waiting,exact,'Bob','Alice','FixtureRealm',1800000001) and waiting.step==4 and waiting.phase=='ready','exact chunk REPORT refused')
local chunkStore={}; local granted=assert(C.HandDecode(chunkWire)); granted.step=3
assert(C.HandApprove(chunkStore,granted,'Alice','Bob','FixtureRealm',1800000001),'chunk GRANT refused')
local work=assert(C.HandStepPlan(chunkStore.active,{},'Bob',{bob=true,bobalt=true}),'granted chunk not runnable by its actor')
assert(work.entries[8] and work.entries[8].account=='Bobalt' and not work.entries[6] and not work.entries[7],'granted chunk leaked other slots')
local foreign=assert(C.HandDecode(chunkWire)); foreign.step=2
assert(not C.HandApprove({},foreign,'Alice','Bob','FixtureRealm',1800000001),'leader chunk granted to Bob')
-- A participant that cannot run its granted chunk answers PAUSE for exactly that run,
-- revision, account claims and step. PAUSE wraps chunked and first-remote runs like
-- REPORT, yet never executes: it is not work, a grant or a report, and never advances.
local function answer(kind,step,edit)
 local t=assert(C.HandDecode(chunkWire)); t.kind=kind; t.step=step
 if edit then edit(t) end
 return t
end
local pauseWire=assert(C.HandEncode(answer('PAUSE',3)),'chunk PAUSE not encodable')
local paused=assert(C.HandDecode(pauseWire),'chunk PAUSE not decodable')
assert(C.HandEncode(paused)==pauseWire and paused.kind=='PAUSE' and paused.step==3 and C.HandRunScope(paused)==C.HandRunScope(chunked),
 'chunk PAUSE not canonical or not bound to the run scope')
local _,_,pauseBase=string.find(pauseWire,'^H6~PAUSE~[0-9,]+~(H5~.+)$')
assert(pauseBase and not C.HandDecode(pauseBase),'chunk PAUSE base decodes as plain H5')
local firstPause=assert(C.HandDecode(assert(C.HandEncode(firstRun('PAUSE')),'first-remote PAUSE not encodable')),'first-remote PAUSE not decodable')
assert(firstPause.kind=='PAUSE' and firstPause.step==1 and firstPause.steps[1].actor=='Bob','first-remote PAUSE not canonical')
assert(not C.HandApprove({},paused,'Alice','Bob','FixtureRealm',1800000001),'PAUSE approved as work')
assert(not C.HandGrantBound(paused,'Alice','Bob',B,A),'PAUSE bound as a grant')
local function held() local t=assert(C.HandDecode(chunkWire)); t.step=3; t.phase='waiting'; return t end
local w=held()
assert(not C.HandReport(w,paused,'Bob','Alice','FixtureRealm',1800000001) and w.step==3 and w.phase=='waiting','PAUSE advanced as a REPORT')
-- Only the leader waiting on that exact step pauses, once; the run never advances. Stale,
-- later, other-revision, other-claim, other-run, other-chunk, wrong-kind, wrong-sender,
-- wrong-leader, other-realm, expired or not-waiting input leaves the run untouched.
assert(type(C.HandRefusal)=='function','leader PAUSE handling missing')
local rejected={
 {why='stale step',r=answer('PAUSE',2)},{why='later step',r=answer('PAUSE',4)},
 {why='other revision',r=answer('PAUSE',3,function(t) t.plan.entries[1].charName='Other' end)},
 {why='other account claim',r=answer('PAUSE',3,function(t) t.accounts[3]=Cid end)},
 {why='other run',r=answer('PAUSE',3,function(t) t.id='1234567890123459' end)},
 {why='other chunk membership',r=answer('PAUSE',3,function(t) t.steps[2].last=6; t.steps[3].first=7 end)},
 {why='REPORT kind',r=answer('REPORT',3)},{why='GRANT kind',r=answer('GRANT',3)},
 {why='wrong sender',r=paused,sender='Carol'},{why='not the leader',r=paused,you='Carol'},
 {why='other realm',r=paused,realm='OtherRealm'},{why='expired',r=paused,wall=1800007200}}
for _,phase in ipairs({'ready','running','interrupted','done','cancelled'}) do table.insert(rejected,{why='leader '..phase,r=paused,phase=phase}) end
for _,case in ipairs(rejected) do
 local t=held(); t.phase=case.phase or 'waiting'
 assert(not C.HandRefusal(t,case.r,case.sender or 'Bob',case.you or 'Alice',case.realm or 'FixtureRealm',case.wall or 1800000001)
  and t.step==3 and t.phase==(case.phase or 'waiting'),'PAUSE accepted or moved the run: '..case.why)
end
assert(C.HandRefusal(w,paused,'bob','Alice','FixtureRealm',1800000001) and w.step==3 and w.phase=='interrupted','exact chunk PAUSE refused or advanced the run')
assert(not C.HandRefusal(w,answer('PAUSE',3),'Bob','Alice','FixtureRealm',1800000002) and w.step==3 and w.phase=='interrupted','duplicate PAUSE accepted')
assert(not C.HandReport(w,answer('REPORT',3),'Bob','Alice','FixtureRealm',1800000002) and w.step==3 and w.phase=='interrupted','REPORT advanced a paused run')
local firstWaiting=firstRun('GRANT'); firstWaiting.phase='waiting'
assert(C.HandRefusal(firstWaiting,firstRun('PAUSE'),'Bob','Alice','FixtureRealm',1800000001) and firstWaiting.step==1 and firstWaiting.phase=='interrupted',
 'first-remote PAUSE refused or advanced the run')
-- The participant answers PAUSE only on request after pausing its own granted step, and
-- only to the leader; a paused step never REPORTs, and a leader never answers PAUSE.
local bobStore={}; local ask=assert(C.HandDecode(chunkWire)); ask.step=3
assert(C.HandApprove(bobStore,ask,'Alice','Bob','FixtureRealm',1800000001),'chunk GRANT refused')
local stalled=bobStore.active
assert(not C.HandOutgoing(stalled,'Bob',true),'PAUSE answered before the step paused')
stalled.phase='interrupted'
local out,to=C.HandOutgoing(stalled,'Bob',true)
assert(out==pauseWire and to=='Alice','paused chunk did not answer its exact PAUSE to the leader')
assert(not C.HandOutgoing(stalled,'Bob') and not C.HandOutgoing(stalled,'Carol',true),'paused chunk REPORTed or answered for another actor')
assert(not C.HandOutgoing(held(),'Alice',true),'leader answered PAUSE')
-- No eight-group cap: twelve alternating chunks over six groups, and a returning grant
-- past step nine is approved after the earlier one completed.
local long={entries={}}
for g=1,6 do
 long.entries[(g-1)*5+1]=row(g<=3 and 'Alicia' or 'Aliana'); long.entries[(g-1)*5+2]=row(g<=3 and 'Bobalt' or 'Bobina')
end
local longActors=C.HandActors(long,'Alice',mine,chunkSrc)
local longRun=assert(C.HandCreate(long,'Safety','Alice','FixtureRealm',longActors,'1234567890123464',1800000000,mine,chunkSrc,true),'twelve-chunk run refused')
assert(table.getn(longRun.steps)==12,'twelve chunks expected, got '..table.getn(longRun.steps))
longRun.kind='GRANT'; longRun.accounts={}; longRun.expires=1800007200; longRun.step=10
for i,s in ipairs(longRun.steps) do longRun.accounts[i]=s.actor=='Bob' and B or A end
local longStore={}
assert(C.HandApprove(longStore,assert(C.HandDecode(assert(C.HandEncode(longRun)))),'Alice','Bob','FixtureRealm',1800000001),'step 10 GRANT refused')
longStore.active.phase='done'; longStore.active.step=11; longRun.step=12
assert(C.HandApprove(longStore,assert(C.HandDecode(assert(C.HandEncode(longRun)))),'Alice','Bob','FixtureRealm',1800000002) and longStore.active.step==12,
 'returning grant past step nine refused')
-- Group commands after a granted chunk reach its own alt's companion (owned by the
-- hire-from character on this account), never another account's companion.
local altRow={kind='normal',account='Bobalt',class='mage',role='rdps'}
local function altComp(owner) return {{name='Comp',owner=owner,class='mage',role='rdps'}} end
assert(table.getn(assert(C.HandScope({altRow},altComp('Bobalt'),'Bob',{},{bob=true,bobalt=true}),'own alt companion out of scope'))==1)
assert(not C.HandScope({altRow},altComp('Bobalt'),'Bob',{},{bob=true}),'alt companion in scope without own evidence')
assert(not C.HandScope({altRow},altComp('Bobalt'),'Bob',{},{bob=true,bobalt=1}),'truthy own evidence accepted')
assert(not C.HandScope({altRow},altComp('Carol'),'Bob',{},{bob=true,bobalt=true,carol=true}),'companion of another hire-from character in scope')
-- Earlier steps of one run claim their own companions first, so a later step's identical
-- row is not mistaken for one already present; a companion no step accounts for stays.
local repeated={entries={[1]=row('Alicia'),[2]=row('Bobalt'),[3]=row('Alicia')}}
local sameRun=assert(C.HandCreate(repeated,'Safety','Alice','FixtureRealm',C.HandActors(repeated,'Alice',mine,chunkSrc),'1234567890123466',1800000000,mine,chunkSrc,true))
local present={{name='One',owner='Alicia',class='mage',role='rdps'},{name='Two',owner='Bobalt',class='mage',role='rdps'},{name='Old',owner='Alicia',class='mage',role='rdps'}}
sameRun.step=3
local left=C.HandUnclaimed(sameRun,present)
assert(table.getn(left)==1 and left[1].name=='Old','earlier steps did not claim their own companions')
sameRun.step=1
assert(table.getn(C.HandUnclaimed(sameRun,present))==3,'the first step claimed companions')
-- A legacy row runs on the account that owns its character: this account when its own
-- list names it, or the one trusted linked snapshot that does. Unknown owners keep the
-- position rule, and the caller learns their names.
do
 local legLinks={}; linkTo(legLinks,'Bob'); linkTo(legLinks,'Carol')
 local legSrc=C.HandRemoteSources({['FixtureRealm;bob']=claim(legLinks,'Bob',B,{'Bob','Bobalt','Bobleg'})},legLinks,'Alice','FixtureRealm')
 local own={alice=true,alicia=true,aliceleg=true}
 local function leg(name) return {kind='legacy',charName=name,sourceName=name,class='mage',role='rdps'} end
 local alone={entries={[1]=leg('Bobleg')}}
 local a,remote=C.HandActors(alone,'Alice',own,legSrc)
 assert(remote and a[1]=='Bob','linked legacy group stayed with the leader: '..tostring(a[1]))
 local beside={entries={[1]=row('Alicia'),[2]=leg('Bobleg')}}
 a=C.HandActors(beside,'Alice',own,legSrc)
 assert(type(a[1])=='table' and a[1][1]=='Alice' and a[1][2]=='Bob','linked legacy beside a local hire not split')
 local run=assert(C.HandCreate(beside,'Safety','Alice','FixtureRealm',a,'1234567890123470',1800000000,own,legSrc,true),'legacy chunk run refused')
 local shape={}; for _,s in ipairs(run.steps) do table.insert(shape,s.group..'='..s.actor..(s.first and ('@'..s.first..'-'..s.last) or '')) end
 assert(table.concat(shape,',')=='1=Alice@1-1,1=Bob@2-2' and run.plan.entries[2].sourceName=='Bobleg','legacy chunk shape: '..table.concat(shape,','))
 a=C.HandActors({entries={[1]=row('Bobalt'),[2]=leg('Aliceleg')}},'Alice',own,legSrc)
 assert(type(a[1])=='table' and a[1][1]=='Bob' and a[1][2]=='Alice','own legacy beside a linked hire went to the link')
 local twoSrc=C.HandRemoteSources({['FixtureRealm;bob']=claim(legLinks,'Bob',B,{'Bob','Splitleg'}),
  ['FixtureRealm;carol']=claim(legLinks,'Carol',Cid,{'Carol','Splitleg'})},legLinks,'Alice','FixtureRealm')
 local none,_,group,unclear=C.HandActors({entries={[6]=leg('Splitleg')}},'Alice',own,twoSrc)
 assert(not none and group==2 and unclear=='Splitleg','legacy claimed by two accounts routed')
 none,_,group,unclear=C.HandActors(alone,'Alice',{alice=true,bobleg=true},legSrc)
 assert(not none and group==1 and unclear=='Bobleg','own and linked legacy claims routed')
 local unknownBoard={entries={[1]=row('Bobalt'),[2]=leg('Mystery')}}
 local u,_,_,_,unknown=C.HandActors(unknownBoard,'Alice',own,legSrc)
 assert(u[1]=='Bob' and type(unknown)=='table' and unknown[1]=='Mystery' and table.getn(unknown)==1,'unknown legacy owner not kept by position or not reported')
end
-- The plan's own commands travel with the run: its group deny and setup rules, and each
-- legacy row's denies and setups, frozen at Execute and carried only inside a GRANT.
-- Every step builds them from that copy, never from whatever profile is open.
do
 local cmdLinks={}; linkTo(cmdLinks,'Bob')
 local cmdSrc=C.HandRemoteSources({['FixtureRealm;bob']=claim(cmdLinks,'Bob',B,{'Bob','Bobalt'})},cmdLinks,'Alice','FixtureRealm')
 local plan={entries={},denyRules={{class='mage',role='rdps',abilities={'Arcane Explosion','Polymorph: Pig'}}},
  setupRules={{class='paladin',role='tank',spec='all',aura='Devotion Aura'}}}
 for i=1,40 do plan.entries[i]={kind='empty'} end
 plan.entries[1]={kind='legacy',charName='Shirmage',sourceName='Shirmage',class='mage',role='rdps',
  denyList={'Frost Nova','Faerie Fire (Feral)'},magic='Amplify',setupRules={{class='mage',role='all',spec='all',drink='40'}}}
 plan.entries[6]=row('Bobalt')
 local mine={alice=true}
 local x=assert(C.HandExtras(plan),'plan commands not frozen')
 local h=assert(C.HandCreate(plan,'Safety','Alice','FixtureRealm',C.HandActors(plan,'Alice',mine,cmdSrc),'1234567890123480',1800000000,mine,cmdSrc,true))
 -- Both accounts' rows get commands: Bob's commands step (the last group's actor) first.
 assert(table.getn(h.steps)==4 and h.steps[3].group==0 and h.steps[3].actor=='Bob' and h.steps[4].group==0 and h.steps[4].actor=='Alice',
  'commands steps missing or out of order')
 h.kind='GRANT'; h.accounts={'1111111111111111',B,B,'1111111111111111'}; h.expires=1800007200; h.extras=x
 local wire=assert(C.HandEncode(h),'GRANT with plan commands not encodable')
 local got=assert(C.HandDecode(wire),'GRANT with plan commands not decodable')
 assert(C.HandEncode(got)==wire and got.extras.legacy[1].denyList[2]=='Faerie Fire (Feral)'
  and got.extras.denyRules[1].abilities[2]=='Polymorph: Pig','plan commands changed on the wire')
 -- Later edits to the open profile never reach the frozen copy.
 plan.entries[1].denyList[1]='Edited'; plan.denyRules[1].abilities[1]='Edited'
 assert(C.HandEncode(h)==wire,'frozen plan commands follow later edits')
 -- Answers never carry them, and they never change the run scope.
 local answer=assert(C.HandDecode(wire)); answer.kind='REPORT'; answer.step=2
 local reportWire=assert(C.HandEncode(answer))
 assert(not string.find(reportWire,'Frost',1,true) and not C.HandDecode(reportWire).extras,'REPORT carried plan commands')
 assert(C.HandRunScope(h)==C.HandRunScope(C.HandDecode(reportWire)),'plan commands changed the run scope')
 -- Hire steps hire only. Each commands step builds exactly the commands a local Execute of
 -- its actor's rows would send after their hires, from the frozen copy.
 local function queue(p)
  for i=1,40 do if not p.entries[i] then p.entries[i]={kind='empty'} end end
  local out={}; for _,q in ipairs(C.HandQueue(p)) do table.insert(out,(q.target or '')..':'..(q.command or '')) end
  return table.concat(out,' | ')
 end
 local frozen={entries={},denyRules={{class='mage',role='rdps',abilities={'Arcane Explosion','Polymorph: Pig'}}},
  setupRules={{class='paladin',role='tank',spec='all',aura='Devotion Aura'}}}
 local function only(first,last,part)
  local p={entries={},denyRules=frozen.denyRules,setupRules=frozen.setupRules}
  for i=first,last do p.entries[i]=C.HandDecode(wire).plan.entries[i] end
  if first==1 then p.entries[1]={kind='legacy',charName='Shirmage',sourceName='Shirmage',class='mage',role='rdps',
   denyList={'Frost Nova','Faerie Fire (Feral)'},magic='Amplify',setupRules={{class='mage',role='all',spec='all',drink='40'}}} end
  for i=1,40 do if not p.entries[i] then p.entries[i]={kind='empty'} end end
  local out={}
  for _,q in ipairs(C.BuildQueue(p)) do
   if (part=='hires')==C.IsHireCommand(q) then table.insert(out,(q.target or '')..':'..(q.command or '')) end
  end
  return table.concat(out,' | ')
 end
 local open={entries={},denyRules={{class='mage',role='rdps',abilities={'Blizzard'}}},setupRules={}}
 got.phase='ready'; got.step=1
 local leaderHires=queue(assert(C.HandStepPlan(got,open,'Alice',mine),'leader step refused'))
 assert(leaderHires==only(1,5,'hires') and not string.find(leaderHires,'deny',1,true),'leader hire step sent commands: '..leaderHires)
 got.step=4
 local leaderStep=queue(assert(C.HandStepPlan(got,open,'Alice',mine),'leader commands step refused'))
 assert(leaderStep==only(1,5,'commands') and string.find(leaderStep,'Shirmag-lite:deny add Frost Nova',1,true)
  and not string.find(leaderStep,'Blizzard',1,true),'leader commands step lost or replaced plan commands: '..leaderStep)
 local store={}
 local grant=assert(C.HandDecode(wire)); grant.step=2
 assert(C.HandApprove(store,grant,'Alice','Bob','FixtureRealm',1800000000),'participant refused a GRANT with plan commands')
 assert(store.active.extras,'participant dropped the plan commands')
 -- Bob's group and his commands step are one batch: its hires, then its commands.
 local bobStep=queue(assert(C.HandStepPlan(store.active,open,'Bob',{bob=true,bobalt=true}),'participant step refused'))
 assert(bobStep==only(6,10,'hires')..' | '..only(6,10,'commands') and string.find(bobStep,'deny add Arcane Explosion',1,true)
  and not string.find(bobStep,'Blizzard',1,true),'participant step used its own profile: '..bobStep)
 -- A run saved before plan commands existed keeps the open profile, as before.
 got.extras=nil
 assert(string.find(queue(assert(C.HandStepPlan(got,open,'Alice',mine))),'Blizzard',1,true),'old run lost its profile rules')
 -- Values outside printable text, and commands for a slot that holds no legacy row, are
 -- refused; so is any wire that is not in its one canonical form.
 local bad={entries={[1]={kind='legacy',charName='Shirmage',sourceName='Shirmage',class='mage',role='rdps',denyList={'Frost|Nova'}}},denyRules={},setupRules={}}
 assert(not C.HandExtras(bad),'unsendable deny accepted')
 local stray=C.HandDecode(wire); stray.extras.legacy[6]={denyList={'Blizzard'}}
 assert(not C.HandEncode(stray),'commands for a normal row encoded')
 local loose=string.gsub(wire,'Frost Nova','Frost_20Nova')
 assert(loose~=wire and not C.HandDecode(loose),'non-canonical escape accepted')
end
-- Consecutive steps of one actor are one batch: one GRANT starts them, one queue runs their
-- slots in board order, and one REPORT for the batch's last step answers the grant. The
-- steps on the wire do not change, so both sides find the same batch.
do
 local bLinks={}; linkTo(bLinks,'Bob')
 local bSrc=C.HandRemoteSources({['FixtureRealm;bob']=claim(bLinks,'Bob',B,{'Bob','Bobalt'})},bLinks,'Alice','FixtureRealm')
 local mine={alice=true,alicia=true}
 local board={entries={[1]=row('Alicia'),[6]=row('Bobalt'),[11]=row('Bobalt'),[16]=row('Alicia'),[21]=row('Alicia')}}
 local h=assert(C.HandCreate(board,'Safety','Alice','FixtureRealm',C.HandActors(board,'Alice',mine,bSrc),'1234567890123490',1800000000,mine,bSrc,true))
 h.kind='GRANT'; h.accounts={'1111111111111111',B,B,'1111111111111111','1111111111111111'}; h.expires=1800007200
 assert(table.getn(h.steps)==5 and C.HandBatchEnd(h,1)==1 and C.HandBatchEnd(h,2)==3 and C.HandBatchEnd(h,4)==5,'batch ends')
 local store={}
 local grant=assert(C.HandDecode(C.HandEncode(h))); grant.step=2
 assert(C.HandApprove(store,grant,'Alice','Bob','FixtureRealm',1800000000),'batch grant refused')
 local plan=assert(C.HandStepPlan(store.active,nil,'Bob',{bob=true,bobalt=true}),'batch plan refused')
 assert(plan.entries[6] and plan.entries[11] and not plan.entries[1] and not plan.entries[16],'batch plan slots')
 store.active.phase='submitted'
 assert(C.HandComplete(store.active,'Bob') and store.active.step==4,'batch did not complete as one step')
 local wire,target=C.HandOutgoing(store.active,'Bob')
 local report=assert(C.HandDecode(wire),'batch report not encodable')
 assert(report.kind=='REPORT' and report.step==3 and target=='Alice','batch report names the wrong step')
 -- The leader waiting on step 2 takes the batch's REPORT and moves to its own step 4.
 local lead=assert(C.HandDecode(C.HandEncode(h))); lead.step=2; lead.phase='waiting'
 assert(C.HandReport(lead,report,'Bob','Alice','FixtureRealm',1800000000) and lead.step==4 and lead.phase=='ready','leader refused the batch report')
 -- A REPORT for the batch's first step only (an older participant) is still taken; the
 -- leader then grants step 3 on its own. A step outside the batch is refused.
 local older=assert(C.HandDecode(C.HandEncode(h))); older.step=2; older.phase='waiting'
 local first=assert(C.HandDecode(wire)); first.step=2
 assert(C.HandReport(older,first,'Bob','Alice','FixtureRealm',1800000000) and older.step==3 and older.phase=='waiting','single-step report refused')
 local outside=assert(C.HandDecode(C.HandEncode(h))); outside.step=2; outside.phase='waiting'
 local far=assert(C.HandDecode(wire)); far.step=4
 assert(not C.HandReport(outside,far,'Bob','Alice','FixtureRealm',1800000000) and outside.step==2,'report outside the batch accepted')
 -- The leader's own steps 4 and 5 are one batch too.
 lead.phase='ready'
 local own=assert(C.HandStepPlan(lead,nil,'Alice',mine),'leader batch refused')
 assert(own.entries[16] and own.entries[21] and not own.entries[11],'leader batch slots')
 lead.phase='submitted'
 assert(C.HandComplete(lead,'Alice') and lead.step==6 and lead.phase=='done','leader batch did not finish the run')
end
-- A leader holds one run at a time, so a new run from it means it ended the old one. A
-- participant's stopped, waiting or unstarted copy of that leader's old run gives way to
-- the new grant and is remembered as cancelled. A run still executing, or another leader's
-- run, still blocks. (Otherwise a stopped copy would refuse every later grant as busy.)
do
 local bLinks={}; linkTo(bLinks,'Bob')
 local bSrc=C.HandRemoteSources({['FixtureRealm;bob']=claim(bLinks,'Bob',B,{'Bob','Bobalt'})},bLinks,'Alice','FixtureRealm')
 local mine={alice=true,alicia=true}
 local board={entries={[1]=row('Alicia'),[6]=row('Bobalt')}}
 -- A run's expiry is fixed when its leader starts it, so a later run expires later.
 local function grant(id,started)
  local h=assert(C.HandCreate(board,'Safety','Alice','FixtureRealm',C.HandActors(board,'Alice',mine,bSrc),id,1800000000,mine,bSrc,true))
  h.kind='GRANT'; h.accounts={'1111111111111111',B}; h.expires=(started or 1800000000)+7200
  local g=assert(C.HandDecode(C.HandEncode(h))); g.step=2; return g
 end
 for _,phase in ipairs({'interrupted','waiting','ready'}) do
  local store={}
  assert(C.HandApprove(store,grant('1234567890123501'),'Alice','Bob','FixtureRealm',1800000000),'first grant refused')
  store.active.phase=phase
  assert(C.HandApprove(store,grant('1234567890123502',1800000100),'Alice','Bob','FixtureRealm',1800000100),'a new run from the same leader was refused over a '..phase..' old run')
  assert(store.active.id=='1234567890123502' and store.seen['1234567890123501'] and store.seen['1234567890123501'].cancelled,
   'the '..phase..' old run was not replaced and remembered as cancelled')
  assert(not C.HandApprove(store,grant('1234567890123501',1800000200),'Alice','Bob','FixtureRealm',1800000200) and store.active.id=='1234567890123502','the replaced run came back')
  assert(not C.HandApprove(store,grant('1234567890123509'),'Alice','Bob','FixtureRealm',1800000200) and store.active.id=='1234567890123502','an older run replaced a newer one')
 end
 local store={}
 assert(C.HandApprove(store,grant('1234567890123503'),'Alice','Bob','FixtureRealm',1800000000))
 store.active.phase='running'
 assert(not C.HandApprove(store,grant('1234567890123504',1800000100),'Alice','Bob','FixtureRealm',1800000100) and store.active.id=='1234567890123503','a running run was replaced')
 store.active.phase='interrupted'
 local other=grant('1234567890123505',1800000100); other.origin='Carol'; other.steps[1].actor='Carol'
 assert(C.HandEncode(other),'fixture: the other leader run does not encode')
 assert(not C.HandApprove(store,other,'Carol','Bob','FixtureRealm',1800000100) and store.active.id=='1234567890123503','another leader replaced the run')
end
-- When one character hires from another on its account, the server may give either one as
-- the companion's owner: the hire-from character or the character that sent the hire. Group
-- commands take both, exact owners first, and never another hire-from character's companion.
-- HandScopeFound also names the slots it could not place.
do
 local own={bob=true,bobalt=true,carol=true}
 local altRow={kind='normal',account='Bobalt',class='mage',role='rdps'}
 local bobRow2={kind='normal',account='Bob',class='mage',role='rdps'}
 assert(table.getn(assert(C.HandScope({altRow},altComp('Bob'),'Bob',{},own),'a companion the actor hired from its alt is out of scope'))==1)
 assert(not C.HandScope({altRow},altComp('Carol'),'Bob',{},own),'another hire-from character in scope')
 local both={{name='Own',owner='Bob',class='mage',role='rdps'},{name='Alt',owner='Bobalt',class='mage',role='rdps'}}
 assert(table.getn(assert(C.HandScope({altRow,bobRow2},both,'Bob',{},own),'an alt row took the companion of the row it belongs to'))==2)
 local legacy={kind='legacy',charName='Bobleg',sourceName='Bobleg',class='mage',role='rdps'}
 local found,missing=C.HandScopeFound({[6]=altRow,[7]=legacy},altComp('Bob'),'Bob',{},own)
 assert(table.getn(found)==1 and found[1].name=='Comp' and table.getn(missing)==1 and missing[1]==7,'unplaced slots not reported')
 -- An earlier step's alt row claims the companion its actor hired, whichever owner the
 -- server gives, so a later step does not take it.
 local bLinks={}; linkTo(bLinks,'Bob')
 local bSrc=C.HandRemoteSources({['FixtureRealm;bob']=claim(bLinks,'Bob',B,{'Bob','Bobalt'})},bLinks,'Alice','FixtureRealm')
 local mine={alice=true,alicia=true}
 local board={entries={[1]=row('Alicia'),[6]=row('Bobalt'),[11]=row('Alicia'),[16]=row('Bobalt')}}
 local h=assert(C.HandCreate(board,'Safety','Alice','FixtureRealm',C.HandActors(board,'Alice',mine,bSrc),'1234567890123510',1800000000,mine,bSrc,true))
 h.step=4
 local live={{name='One',owner='Alicia',class='mage',role='rdps'},{name='Two',owner='Bob',class='mage',role='rdps'},
  {name='Three',owner='Alicia',class='mage',role='rdps'},{name='Four',owner='Bob',class='mage',role='rdps'}}
 local left=C.HandUnclaimed(h,live)
 assert(table.getn(left)==1 and left[1].name=='Four','earlier alt rows did not claim the companions their actor hired')
end
-- Commands steps ("0,actor") end an authorized run, so the plan's commands go out once every
-- hire is done, as a single builder sends them. There is one per actor whose rows get any,
-- after every hire step: the last step's actor first (it goes on without a hand-off), then
-- the rest in board order. Plain processes and malformed rows are refused.
do
 local cLinks={}; linkTo(cLinks,'Bob')
 local cSrc=C.HandRemoteSources({['FixtureRealm;bob']=claim(cLinks,'Bob',B,{'Bob','Bobalt'})},cLinks,'Alice','FixtureRealm')
 local mine={alice=true,alicia=true}
 local function board(rules)
  local p={entries={},denyRules=rules or {},setupRules={}}
  for i=1,40 do p.entries[i]={kind='empty'} end
  p.entries[1]=row('Alicia'); p.entries[6]=row('Bobalt'); p.entries[11]=row('Alicia')
  return p
 end
 local function create(p,id) return assert(C.HandCreate(p,'Safety','Alice','FixtureRealm',C.HandActors(p,'Alice',mine,cSrc),id,1800000000,mine,cSrc,true)) end
 local function shape(h) local out={}; for _,st in ipairs(h.steps) do table.insert(out,st.group..'='..st.actor) end; return table.concat(out,',') end
 assert(shape(create(board(),'1234567890123520'))=='1=Alice,2=Bob,3=Alice','a plan without commands got a commands step')
 local rules={{class='mage',role='rdps',abilities={'Blizzard'}}}
 assert(shape(create(board({{class='warlock',role='rdps',abilities={'Fear'}}}),'1234567890123522'))=='1=Alice,2=Bob,3=Alice',
  'a rule naming no row added a commands step')
 assert(shape(create(board({{class='mage',role='all',abilities={'Blizzard'}}}),'1234567890123523'))=='1=Alice,2=Bob,3=Alice,0=Alice,0=Bob',
  'an every-role rule added no commands step')
 local h=create(board(rules),'1234567890123521')
 assert(shape(h)=='1=Alice,2=Bob,3=Alice,0=Alice,0=Bob','commands steps or their order: '..shape(h))
 -- A legacy row's own commands give its actor a commands step, and only that actor.
 local p=board(); p.entries[7]={kind='legacy',charName='Bobleg',sourceName='Bobleg',class='mage',role='rdps',denyList={'Frost Nova'}}
 assert(shape(create(p,'1234567890123524'))=='1=Alice,2=Bob,3=Alice,0=Bob','legacy commands step')
 -- The wire carries them after every hire step, in one canonical form.
 h.kind='GRANT'; h.accounts={A,B,A,A,B}; h.expires=1800007200; h.extras=assert(C.HandExtras(board(rules)))
 local wire=assert(C.HandEncode(h),'commands steps not encodable')
 local back=assert(C.HandDecode(wire),'commands steps not decodable')
 assert(string.find(wire,'/0,Alice/0,Bob~',1,true) and back.steps[4].group==0 and back.steps[5].actor=='Bob' and C.HandEncode(back)==wire,'commands steps on the wire')
 local function tamper(edit) local t=assert(C.HandDecode(wire)); edit(t); return C.HandEncode(t) end
 assert(not tamper(function(t) t.steps[4].first=1; t.steps[4].last=1 end),'commands step with slots encoded')
 assert(not tamper(function(t) t.steps[5].actor='Alice' end),'two commands steps for one actor encoded')
 assert(not tamper(function(t) t.steps[5].actor='Carol' end),'commands step for an actor with no hire step encoded')
 assert(not tamper(function(t) t.steps[6]={group=3,actor='Alice'}; t.accounts[6]=A end),'hire step after a commands step encoded')
 local raw=assert(C.HandDecode(wire)); raw.kind=nil; raw.accounts=nil; raw.extras=nil
 assert(not C.HandEncode(raw),'plain process with a commands step encoded')
 local loose=string.gsub(wire,'/0,Alice/','/00,Alice/')
 assert(loose~=wire and not C.HandDecode(loose),'non-canonical commands row accepted')
 -- Hire steps hire only. A batch holding a commands step takes every row its actor hired
 -- in the run and sends their commands after its own hires.
 local function lines(plan)
  for i=1,40 do if not plan.entries[i] then plan.entries[i]={kind='empty'} end end
  local out={}; for _,q in ipairs(C.HandQueue(plan)) do table.insert(out,q.kind..(q.sourceEntryIndex and ('@'..q.sourceEntryIndex) or '')) end
  return table.concat(out,',')
 end
 h.phase='ready'; h.step=1
 assert(lines(assert(C.HandStepPlan(h,nil,'Alice',mine)))=='normal@1','first hire step')
 h.step=3
 local last=assert(C.HandStepPlan(h,nil,'Alice',mine))
 assert(last.allRows and last.entries[1] and last.entries[11] and lines(last)=='normal@11,deny','last hire step and Alice commands: '..lines(last))
 h.step=2
 assert(lines(assert(C.HandStepPlan(h,nil,'Bob',{bob=true,bobalt=true})))=='normal@6','Bob hire step')
 h.step=5
 local bob=assert(C.HandStepPlan(h,nil,'Bob',{bob=true,bobalt=true}))
 assert(bob.allRows and bob.entries[6] and not bob.entries[1] and lines(bob)=='deny','Bob commands step: '..lines(bob))
 -- A run without commands steps still sends each step's commands with its hires.
 local old=assert(C.HandDecode(wire)); old.phase='ready'; old.step=1
 for k=5,4,-1 do table.remove(old.steps,k); table.remove(old.accounts,k) end
 assert(lines(assert(C.HandStepPlan(old,nil,'Alice',mine)))=='normal@1,deny','run without commands steps lost its commands')
 -- Earlier steps' claims skip commands steps; approval takes steps past 41.
 h.step=5
 local live={{name='One',owner='Alicia',class='mage',role='rdps'},{name='Two',owner='Bobalt',class='mage',role='rdps'},{name='Three',owner='Alicia',class='mage',role='rdps'}}
 assert(table.getn(C.HandUnclaimed(h,live))==0,'claims over commands steps')
 local store={seen={['1234567890123598']={step=45,expires=1800009999}}}
 local g=assert(C.HandDecode(wire)); g.step=2
 assert(C.HandApprove(store,g,'Alice','Bob','FixtureRealm',1800000000),'a seen run past step 41 broke approval')
end
-- After an account's first GRANT of a run, each hand-off message is short: the run id,
-- the step and a mark of the run's frozen scope, in one packet. The receiver rebuilds the
-- full message from its own copy, and refuses one that does not match that copy exactly.
do
 local sLinks={}; linkTo(sLinks,'Bob')
 local sSrc=C.HandRemoteSources({['FixtureRealm;bob']=claim(sLinks,'Bob',B,{'Bob','Bobalt'})},sLinks,'Alice','FixtureRealm')
 local mine={alice=true,alicia=true}
 local p={entries={},denyRules={{class='mage',role='rdps',abilities={'Blizzard'}}},setupRules={}}
 for i=1,40 do p.entries[i]={kind='empty'} end
 p.entries[1]=row('Alicia'); p.entries[6]=row('Bobalt'); p.entries[11]=row('Alicia'); p.entries[16]=row('Bobalt')
 local h=assert(C.HandCreate(p,'Safety','Alice','FixtureRealm',C.HandActors(p,'Alice',mine,sSrc),'1234567890123530',1800000000,mine,sSrc,true))
 h.kind='GRANT'; h.accounts={}; for i,st in ipairs(h.steps) do h.accounts[i]=string.lower(st.actor)=='bob' and B or A end
 h.expires=1800007200; h.extras=assert(C.HandExtras(p))
 local store={}
 local first=assert(C.HandDecode(C.HandEncode(h))); first.step=2
 assert(C.HandApprove(store,first,'Alice','Bob','FixtureRealm',1800000000))
 store.active.phase='submitted'; assert(C.HandComplete(store.active,'Bob'))
 -- Bob's REPORT goes short, and Alice rebuilds it from her own run.
 local short=assert(C.HandShort(assert(C.HandDecode(assert(C.HandOutgoing(store.active,'Bob'))))),'no short REPORT')
 assert(string.len(short)<=48,'short form takes more than one packet: '..short)
 local lead=assert(C.HandDecode(C.HandEncode(h))); lead.step=2; lead.phase='waiting'
 local report=assert(C.HandExpand(short,lead),'leader could not rebuild the REPORT')
 assert(report.kind=='REPORT' and report.step==2 and not report.extras and C.HandRunScope(report)==C.HandRunScope(lead),'rebuilt REPORT')
 assert(C.HandReport(lead,report,'Bob','Alice','FixtureRealm',1800000001) and lead.step==3,'rebuilt REPORT refused')
 -- Alice's later GRANT to Bob goes short too; Bob rebuilds it with the plan's commands.
 lead.step=4; lead.phase='waiting'
 local grant=assert(C.HandShort(lead),'no short GRANT')
 local again=assert(C.HandExpand(grant,store.active),'participant could not rebuild the GRANT')
 assert(again.kind=='GRANT' and again.step==4 and again.extras and again.extras.denyRules[1].abilities[1]=='Blizzard','rebuilt GRANT lost the plan commands')
 assert(C.HandApprove(store,again,'Alice','Bob','FixtureRealm',1800000002) and store.active.step==4,'rebuilt GRANT refused')
 -- Never another revision, another run or a damaged mark.
 local other=assert(C.HandDecode(C.HandEncode(h))); other.plan.entries[1].tier='t3r'
 assert(not C.HandExpand(grant,other),'short GRANT matched another revision')
 local damaged=string.gsub(grant,'~%x+$','~000000000000')
 assert(damaged~=grant and not C.HandExpand(damaged,store.active),'damaged mark accepted')
 local foreign=assert(C.HandDecode(C.HandEncode(h))); foreign.id='1234567890123531'
 assert(not C.HandExpand(grant,foreign),'short GRANT matched another run')
 for _,bad in ipairs({'H7~X~1234567890123530~4~0123456789ab','H7~G~1234567890123530~04~0123456789ab',
  'H7~G~1234567890123530~4~0123456789','H7~G~123~4~0123456789ab','H7~G~1234567890123530~4~0123456789ab~'}) do
  assert(not C.HandShortParse(bad),'malformed short form accepted: '..bad)
 end
end
-- Ten accounts: Alice and nine linked accounts, each hiring from its own two characters, every
-- row named by a rule. Each account gets one commands step after every hire step. Neither
-- nine or more commands steps nor 39 single-slot hire steps beside them refuse the run.
do
 local names={'Bob','Carol','Dave','Erin','Frank','Grace','Heidi','Ivan','Judy'}
 local tenLinks,claims,mine={},{},{alice=true,alicea=true}
 for k,name in ipairs(names) do
  linkTo(tenLinks,name)
  claims['FixtureRealm;'..string.lower(name)]=claim(tenLinks,name,'20000000000000'..string.format('%02d',k),{name,name..'a'})
 end
 local tenSrc=C.HandRemoteSources(claims,tenLinks,'Alice','FixtureRealm')
 local everyone={'Alice'}; for _,name in ipairs(names) do table.insert(everyone,name) end
 local function plan(spread,hires)
  local p={entries={},denyRules={{class='mage',role='all',abilities={'Blizzard'}}},setupRules={}}
  for i=1,40 do p.entries[i]={kind='empty'} end
  for i=1,hires do
   local k=spread and math.mod(i-1,10)+1 or math.floor((i-1)/4)+1
   p.entries[i]=row(i<=20 and everyone[k] or everyone[k]..'a')
  end
  return p
 end
 for _,case in ipairs({{false,39,'in board order'},{true,30,'slot by slot'},{true,39,'slot by slot, 39 hires'}}) do
  local p=plan(case[1],case[2])
  local h=C.HandCreate(p,'Ten','Alice','FixtureRealm',C.HandActors(p,'Alice',mine,tenSrc),'1234567890123600',1800000000,mine,tenSrc,true)
  assert(h,'a ten-account run '..case[3]..' was refused')
  local hires,commands=0,0
  for _,st in ipairs(h.steps) do if st.group==0 then commands=commands+1 else hires=hires+1 end end
  assert(commands==10,'ten accounts got '..commands..' commands steps '..case[3])
  h.kind='GRANT'; h.accounts={}; h.expires=1800007200; h.extras=assert(C.HandExtras(p))
  for i,st in ipairs(h.steps) do h.accounts[i]=st.actor=='Alice' and A or claims['FixtureRealm;'..string.lower(st.actor)].accountId end
  local wire=assert(C.HandEncode(h),'a ten-account GRANT '..case[3]..' ('..hires..' hire steps) not encodable')
  local back=assert(C.HandDecode(wire),'a ten-account GRANT '..case[3]..' not decodable')
  assert(C.HandEncode(back)==wire and table.getn(back.steps)==hires+10,'a ten-account GRANT changed on the wire')
 end
end
print("Shir's Raid Builder handoff safety tests: PASS")
