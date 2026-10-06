local f=assert(io.open('test_individual_editor.lua','r')); local fixture=f:read('*a'); f:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local function client(name,saved)
 local h=boot(saved,name); h.now=100; h.wall=1800000000; h.sent={}
 h.env.time=function() return h.wall end; h.env.GetTime=function() return h.now end
 h.env.SendChatMessage=function(text,route,lang,target) table.insert(h.sent,{text=text,route=route,target=target}) end
 h.env.SendAddonMessage=function() end
 h.C.PeerOnBuilderOpen(); h.C.peerAutoAttempted=nil
 return h
end
local function link(h,peer)
 local s=h.C.PeerNew(h.env.UnitName('player'),peer,'FixtureRealm')
 s.phase='linked'; s.a='100001'; s.b='100002'; s.started=h.now; s.deadline=h.now+60; s.expires=h.wall+60
 h.C.SyncSelect(s,true); h.C.peerState=s; h.C.SyncStore(); h.C.LinkSave(h.env.ShirsRaidBuilderDB.peerLinks,s,true)
 return s
end
local function hires(h) local n=0; for _,row in ipairs(h.sent) do if row.route=='SAY' then n=n+1 end end; return n end
local function pump(h,seconds)
 for i=1,seconds*4 do
  h.now=h.now+0.25
  for _,w in ipairs(h.frames) do if w.scripts.OnUpdate and w:IsVisible() then h:fire(w,'OnUpdate',0.25) end end
 end
end
-- The retired manual controller: eight editable group actors and per-step buttons.
local retired={['Freeze plan']=true,['Preview step']=true,['Execute step']=true,['Confirm completion']=true,['Send handoff']=true}
local function manual(h)
 local panel,found=h.C.handFrame,{}
 for _,w in ipairs(h.frames) do
  if w:IsVisible() then
   local label=w.kind=='Button' and w.fonts[1] and w.fonts[1]:GetText()
   if label and retired[label] then table.insert(found,label) end
   local p=w.parent; while panel and p and p~=panel do p=p.parent end
   if w.kind=='EditBox' and panel and p==panel then table.insert(found,'editable actor') end
  end
 end
 return table.concat(found,', ')
end
-- Main Hire's group/status entry opens an optional, status-only process panel.
local function status(h)
 h:click(h.env.ShirsRaidBuilderMainFrame.groupActorsBtn)
 local panel=h.C.handFrame
 assert(panel and panel:IsShown() and panel:GetFrameStrata()=='FULLSCREEN_DIALOG','process status panel missing')
 local found=manual(h); assert(found=='','Hire status entry exposes the manual handoff controller: '..found)
 return panel
end
local a=client('Alice'); link(a,'Bob')
-- Saved claims from a completed account sync; Execute freezes them with the participants.
local db=a.env.ShirsRaidBuilderDB; db.syncAccountId='1111111111111111'
db.peerSnapshots['FixtureRealm;bob']={accountId='2222222222222222',source='bob',realm='FixtureRealm',received=1799999400,observed=1799999400,
 entries={{name='Bob',level=60,dungeonLicense='t1d',raidLicense='t2r',observed=1799999400}},authoritative=false}
a.C.LicenseRestoreSaved()
-- Ordinary prepared board: legacy-only groups are the initiator's; the normal row names Bob.
a:preset().entries={[1]={kind='legacy',charName='First',class='mage',role='rdps'},
 [6]={kind='normal',account='Bob',class='mage',role='rdps',race='human',gender='female',tier='t2r',spec='frost'},
 [11]={kind='legacy',charName='Third',class='mage',role='rdps'}}
for i=1,40 do if not a:preset().entries[i] then a:preset().entries[i]={kind='empty'} end end
local main=a.env.ShirsRaidBuilderMainFrame
status(a):Hide()
assert(a:preset().groupActors==nil,'status entry assigned group actors')
a:click(main.executeBtn)
local active=a.env.ShirsRaidBuilderDB.handoff and a.env.ShirsRaidBuilderDB.handoff.active
assert(active and active.phase=='running' and hires(a)==1 and string.find(a.sent[1].text,'First',1,true),
 'one Hire Execute did not start the clear board; status: '..tostring(a.C.handNotice))
local steps={}; for _,row in ipairs(active.steps) do table.insert(steps,row.group..'='..row.actor) end
assert(table.concat(steps,',')=='1=Alice,2=Bob,3=Alice','board identity not derived: '..table.concat(steps,','))
assert(manual(a)=='','Execute exposed manual handoff controls: '..manual(a))
a:click(main.executeBtn); assert(hires(a)==1,'duplicate execution')
-- Interrupted work stays cancellable from the status panel; Stop stays on the builder.
local panel=status(a); a:button(panel,'Cancel process'); a:button(main,'Stop'); panel:Hide()
-- Linked groups auto-run from this single leader Execute (test_run_authorization.lua).
-- Reload mid-group never resumes, replays or retries submitted hires.
local saved=a.env.ShirsRaidBuilderDB
local restored=client('Alice',saved); panel=status(restored)
assert(saved.handoff.active.phase=='interrupted' and hires(restored)==0,'reload resumed actions')
pump(restored,60); assert(hires(restored)==0 and not restored.C.handAuthority,'interrupted process retried hires automatically')
restored:click(restored:button(panel,'Cancel process'))
assert(saved.handoff.active.phase=='cancelled' and not restored.C.handAuthority,'Cancel process did not end the run')
pump(restored,60); assert(hires(restored)==0,'cancelled process executed')
local corrupt=client('Alice',{handoff={active={phase='ready',realm='FixtureRealm',expires=1800000100,steps=false}}})
corrupt:click(corrupt.env.ShirsRaidBuilderMainFrame.groupActorsBtn)
assert(not corrupt.env.ShirsRaidBuilderDB.handoff.active,'invalid saved handoff remained active')
-- Main title stays readable beside the top-bar controls in both modes, at UI scales
-- 1 and 0.64, from the real constructor's anchors. Static stand-in only: harness
-- fixed-pitch glyphs and a 12pt line are rounded up to whole pixels per scale;
-- native font rendering, draw order and hit-testing are not modelled.
do
 local t=client('Tess'); local frame=t.env.ShirsRaidBuilderMainFrame; local title=frame.titleText
 local spot={TOPLEFT={0,1},TOP={0.5,1},TOPRIGHT={1,1},LEFT={0,0.5},CENTER={0.5,0.5},RIGHT={1,0.5},BOTTOMLEFT={0,0},BOTTOM={0.5,0},BOTTOMRIGHT={1,0}}
 local function glyphs(w,s) local n=string.len(w:GetText()); return n>0 and n*math.ceil(w:GetStringWidth()/n*s)/s or 0 end
 -- Main-frame units resolved through the recorded anchors, y up: left,bottom,right,top.
 local function box(w,s)
  if w==frame then return 0,-frame:GetHeight(),frame:GetWidth(),0 end
  local p=assert(w.point,'unanchored main child: '..w.kind)
  local l,b,r,u=box(p[2] or w.parent,s); local at,from=spot[p[3] or p[1]],spot[p[1]]
  local width,height=w:GetWidth(),w:GetHeight()
  if w.kind=='FontString' then width=w.width or glyphs(w,s); height=math.ceil(12*s)/s end
  local x=l+(r-l)*at[1]+(p[4] or 0)-width*from[1]; local y=b+(u-b)*at[2]+(p[5] or 0)-height*from[2]
  return x,y,x+width,y+height
 end
 local function readable(text)
  assert(title and title.parent==frame and title:IsVisible(),'main title missing or hidden')
  assert(title:GetText()==text,'main title "'..tostring(title:GetText())..'" expected "'..text..'"')
  for _,label in ipairs({'X','Link Account','Refresh Synchronization','Hire status','Share Current Plan','Import'}) do t:button(frame,label) end
  for _,s in ipairs({1,0.64}) do
   assert(not title.width or title.width>=glyphs(title,s),'title width truncates "'..text..'" at scale '..s)
   local l,b,r,u=box(title,s)
   assert(l>=0 and r<=frame:GetWidth() and b>=-frame:GetHeight() and u<=0,'title leaves the main frame at scale '..s)
   for _,w in ipairs(t.frames) do
    if w~=title and w.parent==frame and w:IsVisible() then
     local wl,wb,wr,wu=box(w,s)
     local name=(w.label and w.label:GetText()) or (w.kind=='FontString' and 'text "'..w:GetText()..'"') or (w==frame.titleDrag and 'title drag strip') or w.kind
     assert(r<=wl or wr<=l or u<=wb or wu<=b,string.format('"%s" at scale %g intersects %s: title %g,%g..%g,%g vs %g,%g..%g,%g',text,s,name,l,b,r,u,wl,wb,wr,wu))
    end
   end
  end
 end
 local hire="Shir's Raid Builder "..t.env.GetAddOnMetadata('ShirsRaidBuilder','Version')
 readable(hire)
 t:click(frame.modeBtn); readable(hire..' - Sort')
 t:click(frame.modeBtn); readable(hire)
end
-- Idle cost. After login the peer driver runs every frame, with the builder closed and in
-- combat too. A frame must never rerun the board repair (EnsureDB rebuilt all 40 slots and
-- every deny list each frame: about 90 KB of garbage a frame on a real 35-slot board) and
-- must allocate next to nothing, with linked sessions in memory.
do
 local plan={entries={},denyRules={{class='warrior',role='mdps',abilities={'Bloodthirst','Death Wish'}}},setupRules={}}
 for i=1,40 do
  if i<=8 then plan.entries[i]={kind='legacy',charName='Oldname'..string.char(96+i),sourceName='Oldname'..string.char(96+i),class='mage',role='rdps',denyList={'Frost Nova','Blink'}}
  elseif i<=35 then plan.entries[i]={kind='normal',account='Idleown',tier='t2r',class='warrior',role='mdps',spec='default',race='human',gender='male'}
  else plan.entries[i]={kind='empty'} end
 end
 local h=client('Idler',{currentPreset='Default',presets={Default=plan}})
 for _,peer in ipairs({'Peerone','Peertwo','Peerthree'}) do link(h,peer) end
 h.env.ShirsRaidBuilderMainFrame:Hide()
 pump(h,90)
 local repairs,repair=0,h.C.RepairRaidEntries
 h.C.RepairRaidEntries=function(e) repairs=repairs+1; return repair(e) end
 collectgarbage(); collectgarbage(1000000)
 local before=gcinfo()
 pump(h,25)
 local used=(gcinfo()-before)*1024/100
 collectgarbage()
 h.C.RepairRaidEntries=repair
 assert(repairs==0,'100 idle frames ran the board repair '..repairs..' times')
 assert(used<128,'an idle frame allocated '..string.format('%.0f',used)..' bytes')
 -- A lockout read waiting on MCP's table neither re-reads the account nor redraws the
 -- sidebar every frame; it does so once, when the table arrives or the wait ends.
 h.C.RaidReadLocal(); h.C.mcpBase=h.C.MCPGlobal('MCP_SelfLockData'); h.C.mcpPending=h.now
 local reads,read=0,h.C.AccountReadLocal
 h.C.AccountReadLocal=function(r) reads=reads+1; return read(r) end
 pump(h,5)
 local waiting=reads
 pump(h,8)
 h.C.AccountReadLocal=read
 assert(waiting==0 and reads>=1 and reads<=2 and not h.C.mcpPending,'a pending lockout read re-read the account '..waiting..' times in 20 frames, '..reads..' in all')
 -- The Hire status panel writes its progress line only when the run's step or phase changes.
 h.C.OpenHandoff()
 local writes,progress=0,h.C.handFrame.progress
 local set=progress.SetText
 progress.SetText=function(self,text) writes=writes+1; return set(self,text) end
 pump(h,5)
 progress.SetText=nil
 assert(writes==0,'the Hire status panel rewrote an unchanged line '..writes..' times in 20 frames')
 h.C.handFrame:Hide()
end
print("Shir's Raid Builder handoff UI tests: PASS")
