-- Registered source controls; one-line column-major account blocks, no server calls.
local f=assert(io.open('test_individual_editor.lua')); local text=f:read('*a'); f:close()
local at=assert(string.find(text,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(text,1,at-1)..'\nreturn boot'))()
local pass,fail=0,0
local function test(name,fn) local ok,e=pcall(fn); if ok then pass=pass+1; print('PASS '..name) else fail=fail+1; print('FAIL '..name..': '..tostring(e)) end end
local function dump(v)
 if type(v)~='table' then return type(v)=='string' and string.format('%q',v) or tostring(v) end
 local keys,out={},{}; for k in pairs(v) do table.insert(keys,k) end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 for _,k in ipairs(keys) do table.insert(out,'['..dump(k)..']='..dump(v[k])) end; return '{'..table.concat(out,',')..'}'
end
local function start()
 local db={syncAccountId='9999999999999999',currentPreset='Default',presets={Default={entries={{kind='player',charName='Zulu',class='warrior',role='tank'}},denyRules={},setupRules={}}},inviteCharacters={},legacyCharacters={},legacyCharacterRoles={}}
 for _,name in ipairs({'Zulu','Middle','Neon','Longestnamex','Beta'}) do
  db.inviteCharacters[name]={name=name,level=60,dungeonLicense='t5d',raidLicense='t5r',faction='Alliance'}
  db.legacyCharacters[string.lower(name)]='shaman'; db.legacyCharacterRoles[string.lower(name)]='healer'
 end
 local h=boot(db,'Zulu'); local C=h.C
 local function remember(peer,id,names)
  local link=C.PeerNew('Zulu',peer,'FixtureRealm'); link.phase='linked'; assert(C.LinkSave(db.peerLinks,link,true))
  local snap={accountId=id,source=string.lower(peer),realm='FixtureRealm',received=1800000000,observed=1800000000,authoritative=false,entries={}}
  for _,name in ipairs(names) do table.insert(snap.entries,{name=name,level=60,dungeonLicense='t3d',raidLicense='t4r',faction='Alliance',observed=1800000000}) end
  db.peerSnapshots['FixtureRealm;'..string.lower(peer)]=snap
 end
 remember('Peerone','2222222222222222',{'Aardvark','Remoteone'})
 remember('Peertwo','1111111111111111',{'Another','Remotetwo'})
 h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn)
 return h,h.C.plannerFrame,remember
end
local function geometry(p)
 local boxes={}
 for _,row in ipairs(p.sourceRows) do if row.source then
  assert(row:GetHeight()<=28,'source still uses multiple selection lines')
  assert(not row.detail or not row.detail:IsVisible(),'per-source metadata line remains')
  local x,y=row.point[4],-row.point[5]; local w,height=row:GetWidth(),row:GetHeight()
  assert(x>=0 and x+w<=p.sourceContent:GetWidth() and y>=0 and y+height<=p.sourceContent:GetHeight(),'source outside list')
  for _,b in ipairs(boxes) do assert(x>=b.x+b.w or b.x>=x+w or y>=b.y+b.h or b.y>=y+height,'source row overlap') end
  table.insert(boxes,{x=x,y=y,w=w,h=height})
  local last=0
  for _,c in ipairs({row.normalCheck,row.tierButton,row.legacyCheck,row.roleButton}) do
   local left,top=c.point[4],-c.point[5]
   assert(top==0 and c:IsVisible(),'selection controls not aligned/reachable on one row')
   assert(left>=last and left+c:GetWidth()<=w and c:GetHeight()<=height,'click regions overlap or leave row')
   last=left+c:GetWidth()
  end
  local label=row.normalCheck.label
  assert(label:GetStringWidth()<=label:GetWidth(),'long character label clipped')
  assert(label.point[4]+label:GetWidth()<=row.tierButton.point[4],'name overlaps tier hit area')
  assert(row.legacyCheck.label.point[4]+row.legacyCheck.label:GetWidth()<=row.roleButton.point[4],'legacy label overlaps role')
  assert(row.tierButton.label:GetStringWidth()+16<=row.tierButton:GetWidth(),'tier text collides with dropdown arrow')
 end end
end

test('actual source list is current-account first with compact column-major rows',function()
 local h,p=start(); local remote,account,previous=false,nil,nil
 for i,s in ipairs(p.sources) do
  if not s.localSource then remote=true end
  assert(not (remote and s.localSource),'linked names interleave the current ACCOUNT characters')
  if account==s.accountId then assert(string.lower(previous)<string.lower(s.name),'within-account order unstable') else previous=nil end
  if account and not s.localSource and not p.sources[i-1].localSource then assert(account<=s.accountId,'linked account blocks interleave') end
  account=s.accountId; previous=s.name
 end
 geometry(p)
 local lastX,lastY=-1,-1
 for _,r in ipairs(p.sourceRows) do if r.source then
  local x,y=r.point[4],-r.point[5]
  assert(x>=lastX,'row-major source flow remains')
  if x==lastX then assert(y>lastY,'column does not fill top to bottom') else assert(y==0,'next column does not start at top') end
  lastX=x; lastY=y
 end end
 assert(p.sourceMax==0 and not p.nextSources and not p.previousSources)
end)

test('one-line relayout preserves independent choices and reload state by full identity',function()
 local h,p=start(); local chosen
 for _,row in ipairs(p.sourceRows) do if row.source.localSource then chosen=row; break end end
 assert(chosen); local key=chosen.source.key
 chosen.normalCheck:SetChecked(1); h:fire(chosen.normalCheck,'OnClick')
 h:choose(chosen.tierButton,'t1r'); chosen.legacyCheck:SetChecked(1); h:fire(chosen.legacyCheck,'OnClick'); h:choose(chosen.roleButton,'mdps')
 local expected=dump(p.request.sources[key]); h.C.PlannerPaintSources(); geometry(p)
 assert(dump(p.request.sources[key])==expected and chosen.roleButton.label:GetText()=='mdps')
 local db=assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))()
 h=boot(db,'Zulu'); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn); p=h.C.plannerFrame
 assert(dump(p.request.sources[key])==expected); geometry(p)
end)

test('same-name account claims remain separate disabled identities rather than merging',function()
 local h,p,remember=start()
 remember('Peertwo','1111111111111111',{'Aardvark','Remotetwo'})
 h.C.ClosePlanner(); h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn); p=h.C.plannerFrame
 local count,keys=0,{}
 for _,row in ipairs(p.sourceRows) do if row.source and row.source.name=='Aardvark' then
  count=count+1; assert(not keys[row.source.key],'duplicate identity key'); keys[row.source.key]=true
  assert(row.source.accountId and row.source.conflict and not row.normalCheck:IsEnabled() and not row.legacyCheck:IsEnabled(),'ambiguous claim gained authority')
  assert(string.find(row.normalCheck.tip,'ambiguous',1,true),'safety warning absent from tooltip')
 end end
 assert(count==2,'same-name sources from separate accounts were merged')
 geometry(p)
end)
print("Shir's Raid Builder compact sources tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('compact source regressions failed') end
