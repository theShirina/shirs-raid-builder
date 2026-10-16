-- Full source identities are not shortened live aliases. Actual UI/Execute paths.
local f=assert(io.open('test_individual_editor.lua'));local text=f:read('*a');f:close();local at=assert(string.find(text,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))()
local passed,failed=0,0
local function test(n,fn)local ok,e=pcall(fn);if ok then passed=passed+1;print('PASS '..n) else failed=failed+1;print('FAIL '..n..': '..tostring(e)) end end
local function start()
 local db={syncAccountId='1111111111111111',currentPreset='Default',presets={Default={entries={},denyRules={},setupRules={}}},inviteCharacters={},legacyCharacters={shirsham='shaman',shirshadow='priest'},legacyCharacterRoles={shirsham='mdps',shirshadow='rdps'}}
 for _,n in ipairs({'Alice','Shirsham','Shirshadow'}) do db.inviteCharacters[n]={name=n,level=60,dungeonLicense='t5d',raidLicense='t5r',faction=n=='Shirsham' and 'Horde' or 'Alliance'} end
 local h=boot(db,'Alice');h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);local p=h.C.plannerFrame
 for _,r in ipairs(p.sourceRows) do if r.source.name~='Alice' then r.legacyCheck:SetChecked(1);h:fire(r.legacyCheck,'OnClick') end end
 return h,p
end
local function dump(v) if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end;local out={};for k,x in pairs(v) do table.insert(out,'['..dump(k)..']='..dump(x)) end;table.sort(out);return '{'..table.concat(out,',')..'}' end

test('exact distinct full sources sharing prefix build count save refresh reload and wire intact',function()
 local h,p=start();h:click(p.buildButton);local r=assert(p.proposal,p.message:GetText());assert(r.legacy==2 and r.total==3)
 local seen={};for _,e in ipairs(r.plan.entries) do if e.kind=='legacy' then seen[e.sourceName]=h.C.BuildHireCommand(e);assert(e.charName==e.sourceName) end end
 assert(seen.Shirsham=='.z addlegacy "Shirsham" mdps' and seen.Shirshadow=='.z addlegacy "Shirshadow" rdps')
 local wire=assert(h.C.PlanDecode(assert(h.C.PlanEncode(r.plan,'hire','Full names'))));local count=0;for _,e in ipairs(wire.entries) do if e.kind=='legacy' then assert(seen[e.sourceName]==h.C.BuildHireCommand(e));count=count+1 end end;assert(count==2)
 local saved=dump(r.plan.entries);p.nameInput:SetText('Full names');h:click(p.applyButton);h.env.RefreshComposition();assert(dump(h:preset().entries)==saved)
 local fresh=boot(assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))(),'Alice');assert(dump(fresh:preset().entries)==saved)
 local sources=fresh.C.PlannerReadSources();local selected=fresh.C.PlannerRestoreSources(fresh.env.ShirsRaidBuilderDB,'FixtureRealm',sources)
 for _,s in ipairs(sources) do if seen[s.name] then assert(s.accountId=='1111111111111111' and selected[s.key].includeLegacy) end end
end)
test('ambiguous live alias is a distinct Execute safety error, no send or arbitrary skip',function()
 local h,p=start();h:click(p.buildButton);assert(p.proposal,p.message:GetText());p.nameInput:SetText('Collision');h:click(p.applyButton)
 local sent=0;h.env.SendChatMessage=function()sent=sent+1 end;h.env.SendAddonMessage=function()sent=sent+1 end
 local slots=h.C.PresentLegacySlots(h:preset().entries,{['Shirsha-lite']=true});assert(not next(slots),'ambiguous alias arbitrarily consumed a full identity')
 h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn);assert(sent==0,'ambiguous live name started spending/transport')
 assert(h.C.LegacyTargetError(h:preset().entries) and string.find(h.C.handNotice or '','Shirsha-lite',1,true),'real live-address limit not explained')
end)
test('unknown lite-only label never fabricates source or strips suffix to hire',function()
 local h=start();local C=h.C;C.knownCharacterNames={'Shirsham','Shirshadow'}
 local e={kind='legacy',charName='Shirsha-lite',class='priest',role='rdps'}
 assert(C.GetLegacyHireName(e)=='' and not C.BuildHireCommand(e),'display prefix became a fabricated full hire')
 local n=C.NormalizeBoardEntry(e);assert(not n.sourceName and n.charName=='Shirsha-lite','normalization manufactured identity')
 assert(not C.PlanEntry(n),'unknown alias authorized on wire')
end)
test('explicit full identity is never rewritten by first matching seven-letter prefix',function()
 local h=start();local C=h.C;C.knownCharacterNames={'Mageowner','Mageowntwo'}
 local e={kind='legacy',sourceName='Mageown',charName='Mageown',class='mage',role='rdps'}
 assert(C.ResolveLegacyHireName(e)=='Mageown' and C.BuildHireCommand(e)=='.z addlegacy "Mageown" rdps')
end)
test('real duplicates and conflicting account ownership still fail closed',function()
 local h,p=start();local C=h.C;local sources=p.sources
 for _,s in ipairs(sources) do if s.name=='Shirshadow' then s.conflict=true end end
 local r,why=C.PlannerBuild(p.base,sources,p.request);assert(not r and string.find(why,'account identity',1,true))
 local e={kind='legacy',sourceName='Shirsham',charName='Shirsham',class='shaman',role='mdps'}
 r,why=C.PlannerBuild({entries={e,C.PlannerCopy(e)}},{},{counts={},sources={}});assert(not r and why)
end)
print("Shir's Raid Builder full identity tests: "..(failed==0 and 'PASS' or 'FAIL')..' ('..passed..' passed, '..failed..' failed)');assert(failed==0,'full identity regressions failed')
