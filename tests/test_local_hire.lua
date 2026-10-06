-- Ordinary Hire on the real UI fixture: one Execute runs a prepared plan whose
-- normal hires come from this account's own hiring characters. No Group actors,
-- links, synchronization or handoff steps are involved. Exact Lua 5.0.3.
local f=assert(io.open('test_individual_editor.lua','r')); local fixture=f:read('*a'); f:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local entries={[1]={kind='normal',account='Carol',tier='t2r',class='mage',role='rdps',spec='frost',race='human',gender='female'},
 [6]={kind='legacy',charName='Second',class='mage',role='rdps'}}
for i=1,40 do if not entries[i] then entries[i]={kind='empty'} end end
-- Carol is a level-60 hiring character on Alice's own account, as listed by Microbot.
local h=boot({currentPreset='Default',presets={Default={entries=entries,denyRules={},setupRules={}}},
 inviteCharacters={Alice={name='Alice',level=60,raidLicense='t2r',dungeonLicense='t1d'},
  Carol={name='Carol',level=60,raidLicense='t2r',dungeonLicense='t1d'}}},'Alice')
local now,said,other=100,{},{}
h.env.GetTime=function() return now end
h.env.SendChatMessage=function(text,route,language,target)
 if route=='SAY' then table.insert(said,text) else table.insert(other,tostring(route)..' '..tostring(target)..' '..text) end
end
h.env.SendAddonMessage=function() end
h:click(h.env.ShirsRaidBuilderMainFrame.executeBtn)
assert(said[1]=='.z addinvite Carol t2r mage rdps frost human female',
 'ordinary Hire Execute did not hire from an own-account character; status: '..tostring(h.C.handNotice))
for _=1,80 do
 now=now+0.25
 for _,w in ipairs(h.frames) do if w.scripts.OnUpdate and w:IsVisible() then h:fire(w,'OnUpdate',0.25) end end
end
assert(table.getn(said)==2 and said[2]=='.z addlegacy "Second" rdps','ordinary Hire did not finish the prepared plan: '..table.concat(said,' | '))
assert(table.getn(other)==0,'ordinary Hire whispered handoff or peer traffic: '..table.concat(other,' | '))
local db=h.env.ShirsRaidBuilderDB
assert(not (db.handoff and db.handoff.active) and not h.C.handAuthority,'ordinary Hire created a cross-account process')
-- Pacing: a hire waits until the last hired companion has joined the group (the server
-- has finished that hire) plus 1 s; with no join it waits the 7.5-8.5 s settle time. The
-- first whisper after the last hire always waits the settle time, and a whisper to a legacy
-- companion also waits (up to 20 s) for it to be in the group.
local function paced(joinAfter)
 local timed={[1]={kind='normal',account='Carol',tier='t2r',class='mage',role='rdps',spec='frost',race='human',gender='female'},
  [2]={kind='normal',account='Carol',tier='t2r',class='warlock',role='rdps',spec='default',race='human',gender='female'},
  [3]={kind='legacy',charName='Second',sourceName='Second',class='mage',role='rdps',denyList={'Blizzard'}}}
 for i=1,40 do if not timed[i] then timed[i]={kind='empty'} end end
 local t=boot({currentPreset='Default',presets={Default={entries=timed,denyRules={},setupRules={}}},
  inviteCharacters={Alice={name='Alice',level=60,raidLicense='t2r',dungeonLicense='t1d'},
   Carol={name='Carol',level=60,raidLicense='t2r',dungeonLicense='t1d'}}},'Alice')
 local clock,sent,party,joins=100,{},{},{}
 t.env.GetTime=function() return clock end
 t.env.SendChatMessage=function(text,route,language,target)
  table.insert(sent,{at=clock,text=text,route=route,target=target})
  if joinAfter and route=='SAY' then
   local _,_,real=string.find(text,'^%.z addlegacy "(%a+)"')
   table.insert(joins,{at=clock+joinAfter,name=real and t.C.NormalizeLegacyName(real) or 'Comp'..string.char(96+table.getn(sent))})
  end
 end
 t.env.SendAddonMessage=function() end
 t.env.GetNumPartyMembers=function() return table.getn(party) end
 t.env.UnitName=function(unit)
  if unit=='player' then return 'Alice' end
  local _,_,n=string.find(tostring(unit),'^party(%d+)$')
  return n and party[tonumber(n)]
 end
 t:click(t.env.ShirsRaidBuilderMainFrame.executeBtn)
 for _=1,240 do
  clock=clock+0.25
  local k=1
  while joins[k] do if joins[k].at<=clock then table.insert(party,table.remove(joins,k).name) else k=k+1 end end
  for _,w in ipairs(t.frames) do if w.scripts.OnUpdate and w:IsVisible() then t:fire(w,'OnUpdate',0.25) end end
 end
 local lines={}; for _,s in ipairs(sent) do table.insert(lines,string.format('%.2f %s %s',s.at,s.route,s.text)) end
 local all=table.concat(lines,' | ')
 assert(table.getn(sent)==4 and sent[3].text=='.z addlegacy "Second" rdps' and sent[4].route=='WHISPER'
  and sent[4].target=='Second-lite' and sent[4].text=='deny add Blizzard','paced plan did not finish in order: '..all)
 return sent,all,t.messages
end
local sent,all=paced(1.5)
for i=2,3 do
 local gap=sent[i].at-sent[i-1].at
 assert(gap>=2.5 and gap<=2.75,'hire '..i..' came '..gap..' s after the previous hire, not 1 s after its companion joined: '..all)
end
assert(sent[4].at-sent[3].at>=7.5,'whisper sent before the server settle time after the last hire: '..all)
local notes
sent,all,notes=paced(nil)
for i=2,3 do assert(sent[i].at-sent[i-1].at>=7.5,'hire '..i..' did not wait the settle time without a join: '..all) end
assert(sent[4].at-sent[3].at>=27.5,'legacy whisper did not wait for its companion: '..all)
local noted=false
for _,m in ipairs(notes) do if string.find(m,'Second-lite is not in the group; whispering anyway.',1,true) then noted=true end end
assert(noted,'missing legacy companion was not reported')
-- A queue can start on a held command: Sort mode's Whispers with no group rules starts on a
-- legacy setup, as a run's commands step can. It goes out once, after the companion list,
-- never also before it.
do
 local rows={[1]={kind='legacy',charName='Second',sourceName='Second',class='mage',role='rdps',magic='Amplify',denyList={'Blizzard'}}}
 for i=1,40 do if not rows[i] then rows[i]={kind='empty'} end end
 local t=boot({uiMode='sort',currentPreset='Default',currentSortPreset='Default',presets={Default={entries={},denyRules={},setupRules={}}},
  sortPresets={Default={entries=rows,denyRules={},setupRules={},sortLayout=true}}},'Alice')
 local clock,sent,replies=100,{},{}
 t.env.GetTime=function() return clock end
 t.env.SendChatMessage=function(text,route,language,target) table.insert(sent,tostring(target)..': '..text) end
 t.env.SendAddonMessage=function(prefix,text) if prefix=='nexus' and text=='GRINFO:ALL:FULL' then table.insert(replies,'[nexus] GRINFO:ALL:FULL') end end
 t.env.GetNumPartyMembers=function() return 1 end
 t.env.UnitName=function(unit) if unit=='player' then return 'Alice' elseif unit=='party1' then return 'Second-lite' end end
 t.C.StartWhispers()
 for _=1,200 do
  clock=clock+0.25
  for _,w in ipairs(t.frames) do if w.scripts.OnUpdate and w:IsVisible() then t:fire(w,'OnUpdate',0.25) end end
  while table.getn(replies)>0 do
   local text=table.remove(replies,1)
   t.env.event='CHAT_MSG_ADDON'; t.env.arg2='nexus'
   for _,w in ipairs(t.frames) do if w.events.CHAT_MSG_ADDON and w.scripts.OnEvent then t:fire(w,'OnEvent',text) end end
  end
 end
 local all=table.concat(sent,' | ')
 local magic=0; for _,line in ipairs(sent) do if line=='Second-lite: set magic amplify' then magic=magic+1 end end
 assert(magic==1,'held legacy setup whispered '..magic..' times: '..all)
 assert(sent[table.getn(sent)]=='Second-lite: deny add Blizzard','legacy deny list missing or out of order: '..all)
end
print("Shir's Raid Builder local hire tests: PASS")
