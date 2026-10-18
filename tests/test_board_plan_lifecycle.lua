-- Corrected incident: remove human40, drag human39 to40, then switch plans.
-- Whole production callbacks in exact Lua 5.0.3; native backdrop UVs/pixels are not mocked.
local f=assert(io.open('test_individual_editor.lua'));local src=f:read('*a');f:close()
local stop=assert(string.find(src,'\nlocal failures, passes=',1,true));src=string.sub(src,1,stop-1)
local function replace(text,old,new)
 local a,b=string.find(text,old,1,true);assert(a,'fixture extension anchor missing');return string.sub(text,1,a-1)..new..string.sub(text,b+1)
end
src=replace(src,'local function boot(saved, player)','local function boot(saved, player, class)')
src=replace(src,"env.UnitClass=function() return 'Warrior','WARRIOR' end","env.UnitClass=function() return class or 'Shaman',string.upper(class or 'Shaman') end")
local insert=assert(string.find(src,'    env.CreateFrame=widget;',1,true))
local geometry=[[
    local factors={TOPLEFT={0,1},TOP={0.5,1},TOPRIGHT={1,1},LEFT={0,0.5},CENTER={0.5,0.5},RIGHT={1,0.5},BOTTOMLEFT={0,0},BOTTOM={0.5,0},BOTTOMRIGHT={1,0}}
    function methods:ClearAllPoints() self.point=nil;self.points={};self.allPoints=nil end
    function methods:SetPoint(point,relative,relativePoint,x,y)
        assert(type(point)=='string' and type(relative)=='table' and type(relativePoint)=='string','fixture needs explicit anchor')
        self.points=self.points or {};local p={point,relative,relativePoint,x or 0,y or 0};local found=false
        for i,old in ipairs(self.points) do if old[1]==point then self.points[i]=p;found=true end end
        if not found then table.insert(self.points,p)end;self.point=p
    end
    function methods:SetAllPoints(relative)
        self:ClearAllPoints();self.allPoints=relative or self.parent
        self:SetPoint('TOPLEFT',self.allPoints,'TOPLEFT',0,0);self:SetPoint('BOTTOMRIGHT',self.allPoints,'BOTTOMRIGHT',0,0)
    end
    local function bounds(w,seen)
        if w==env.UIParent then return 0,0,1920,1080 end
        seen=seen or {};assert(not seen[w],'anchor cycle');seen[w]=true
        if w.allPoints then local l,b,ww,hh=bounds(w.allPoints,seen);seen[w]=nil;return l,b,ww,hh end
        local width,height=w:GetWidth(),w:GetHeight();local p=w.points and w.points[1]
        if not p then seen[w]=nil;return 0,0,width,height end
        local l,b,rw,rh=bounds(p[2],seen);local a,r=factors[p[1] ],factors[p[3] ];assert(a and r,'unknown anchor')
        seen[w]=nil;return l+rw*r[1]+p[4]-width*a[1],b+rh*r[2]+p[5]-height*a[2],width,height
    end
    function methods:GetLeft()local l=bounds(self);return l end
    function methods:GetBottom()local _,b=bounds(self);return b end
    function methods:GetRight()local l,_,w=bounds(self);return l+w end
    function methods:GetTop()local _,b,_,h=bounds(self);return b+h end
    function methods:SetAlpha(v)self.alpha=v end
    function methods:GetAlpha()return self.alpha or 1 end
    function methods:SetMovable(v)self.movable=v end
    function methods:StartMoving()self.moving=true end
    function methods:StopMovingOrSizing()self.moving=false end
    function methods:RegisterForDrag(...)self.dragButtons=arg end
    function methods:SetTexture(...)self.texture=arg end
    function methods:SetTexCoord(...)self.texCoord=arg end
    function methods:SetVertexColor(...)self.vertex=arg end
    function methods:SetBlendMode(v)self.blend=v end
    local createFontString=methods.CreateFontString
    function methods:CreateFontString(name,layer,template)
        local text=createFontString(self,name,layer,template);text.layer=layer;return text
    end
    local setBackdrop=methods.SetBackdrop
    function methods:SetBackdrop(v)
        self.backdropCalls=(self.backdropCalls or 0)+1
        self.backdropAt={width=self:GetWidth(),height=self:GetHeight(),point=self.point,shown=self:IsShown()}
        setBackdrop(self,v)
    end
]]
src=string.sub(src,1,insert-1)..geometry..string.sub(src,insert)
local boot=assert(loadstring(src..'\nreturn boot'))()
local pass,fail,states=0,0,0
local function test(name,fn)
 local ok,e=pcall(fn);if ok then pass=pass+1;print('PASS '..name)else fail=fail+1;print('FAIL '..name..': '..tostring(e))end
end
local function copy(v)
 if type(v)~='table'then return v end;local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out
end
local function dump(v)
 if type(v)~='table'then return type(v)=='string'and string.format('%q',v)or tostring(v)end
 local out={};for k,x in pairs(v)do table.insert(out,'['..dump(k)..']='..dump(x))end;table.sort(out);return '{'..table.concat(out,',')..'}'
end
local function human(name,class,role)return {kind='player',charName=name,class=class or 'shaman',role=role or 'rdps'}end
local function normal()return {kind='normal',account='Ownalt',tier='t3r',class='mage',role='rdps',spec='fire',race='gnome',gender='female'}end
local function plan()return {entries={},denyRules={},setupRules={}}end
local function safety(h)
 h.actions={}
 for _,key in ipairs({'SendChatMessage','SendAddonMessage','UninviteByName','UninviteUnit','InviteByName','ConvertToRaid','SetRaidSubgroup','SwapRaidSubgroup'})do
  local name=key;h.env[name]=function()table.insert(h.actions,name);error('unexpected game action: '..name)end
 end
 return h
end
local function fixture(mover,otherShape,preferred)
 local a,b=plan(),plan();a.plannerPlayerSlot=preferred
 for i=1,40 do a.entries[i]={kind='empty'}end
 a.entries[2]=normal();a.entries[7]={kind='legacy',charName='Legacy',sourceName='Legacy',class='warlock',role='rdps',denyList={'Rain of Fire'}}
 a.entries[39]=human(mover=='self'and'Tester'or'Ownalt')
 a.entries[40]=human(mover=='self'and'Ownalt'or'Otheralt','priest','healer')
 if mover~='self'then a.entries[1]=human('Tester')end
 if otherShape=='full'then
  for i=1,39 do b.entries[i]=normal()end;b.entries[40]=human('Tester')
 elseif otherShape=='mixed'then
  b.entries[1]=human('Tester');b.entries[39]=normal();b.entries[40]={kind='guest',charName='Visitor',class='priest',role='healer'}
 elseif otherShape=='sparse'then
  b.entries[40]=human('Tester')
 end
 local db={syncAccountId='1111111111111111',currentPreset='A',presets={A=a,B=b},characterRoles={Tester='rdps',Ownalt='rdps',Otheralt='healer'},
  inviteCharacters={},knownCharacters={Tester=true,Ownalt=true,Otheralt=true},localAccountRows={FixtureRealm={}}}
 for _,name in ipairs({'Tester','Ownalt','Otheralt'})do
  db.inviteCharacters[name]={name=name,level=60,raidLicense='t3r',dungeonLicense='t3d',faction='Horde'}
  table.insert(db.localAccountRows.FixtureRealm,{name=name,level=60,raidLicense='t3r',dungeonLicense='t3d',faction='Horde',observed=1800000000})
 end
 return safety(boot(db,'Tester','Shaman'))
end
local function row(h,index)
 local kind=h.C.IsFilledEntry(h:preset().entries[index])and'entry'or'empty';local w=h.C.boardPools[kind][index]
 assert(w and w:IsVisible()and w.boardIndex==index,'visible card missing at '..index);return w
end
local function countSelf(h)
 local n,at=0,nil;for i,e in ipairs(h:preset().entries)do if e.kind=='player'and string.lower(e.charName or'')=='tester'then n=n+1;at=i end end
 assert(n==1,'mandatory current-character count '..n);return at
end
local function absent(h,name)
 for _,e in ipairs(h:preset().entries)do assert(not(e.kind=='player'and e.charName==name),'removed human returned')end
end
local function ghost(h)
 local found
 for _,w in ipairs(h.frames)do if w.kind=='Frame'and w:GetFrameStrata()=='TOOLTIP'and w.tier and w.line1 and w.line2 then assert(not found,'duplicate drag ghost');found=w end end
 return found
end
local function stable(h)
 local expected,seen,active={}, {}, {};local y=-2;local parent;local count=0
 for group=1,8 do
  local header=h.C.boardPools.header[group];assert(header and header:IsVisible(),'header missing')
  assert(header.point[4]==2 and header.point[5]==y and table.getn(header.points)==1,'stale header geometry')
  assert(header.headerText.layer=='OVERLAY' or header.headerText.layer==nil,'header text layer changed')
  y=y-19
  if not string.find(header.headerText:GetText(),'[+]',1,true)then
   for slot=0,4 do local index=(group-1)*5+slot+1;expected[index]={2+slot*102,y};count=count+1 end
   y=y-32
  end
 end
 local visible=0
 for kind,pool in pairs(h.C.boardPools)do for index,w in pairs(pool)do
  if kind~='header'then
   if w:IsVisible()then
    visible=visible+1;assert(expected[index]and not seen[index],'duplicate/unexpected visible pool at '..index);seen[index]=true
    assert(w==row(h,index)and w.boardEntry==h:preset().entries[index],'stale pooled identity')
    assert(w:GetAlpha()==1 and w:IsEnabled(),'faded/disabled active row')
    assert(table.getn(w.points)==1 and w.point[1]=='TOPLEFT','stale row anchors')
    assert(w.point[4]==expected[index][1]and w.point[5]==expected[index][2],'wrong board position')
    assert(w:GetWidth()==100 and w:GetHeight()==28,'wrong card size')
    parent=parent or w.parent;assert(w.parent==parent,'reused row has a different parent')
    assert(w:GetFrameStrata()==parent:GetFrameStrata()and w:GetFrameLevel()==parent:GetFrameLevel()+1,'row strata/level drift')
    assert(w.backdrop.edgeSize==8 and w.backdrop.edgeFile=='Interface\\Tooltips\\UI-Tooltip-Border','border metadata changed')
    assert(w.backdropAt.width==100 and w.backdropAt.height==28 and w.backdropAt.point[2]==parent,'SetBackdrop before card geometry')
    if kind=='entry'then
     assert(w.line1:IsVisible()and w.line2:IsVisible(),'hidden card text')
     assert(w.line1:GetText()==tostring(index)..' '..h.C.LayoutLabel(h:preset().entries[index]),'stale number/name')
     assert(table.getn(w.line1.points)==2 and w.line1.points[1][2]==w and w.line1.points[2][2]==w,'detached text anchors')
     if w.boardEntry.kind=='player'then assert(w.borderColor[1]==0.95 and w.borderColor[2]==0.78 and w.borderColor[3]==0.28,'human gold border lost')end
     if string.lower(w.boardEntry.charName or'')=='tester'then assert(not w.removeButton or not w.removeButton:IsShown(),'current self has removal X')end
    else
     assert(w.emptyText:GetText()=='empty'and w.emptyText:IsVisible(),'stale empty text')
     assert(w.quickHighlight.layer=='OVERLAY'and w.quickHighlight.allPoints==w and not w.quickHighlight:IsShown(),'unbounded/stuck hover texture')
    end
    table.insert(active,w)
   else
    assert(not w.boardEntry and not w.boardIndex,'inactive pool retains identity')
    assert(not w.line1 or not w.line1:IsShown(),'released text remains shown')
    assert(not w.quickHighlight or not w.quickHighlight:IsShown(),'released hover remains shown')
    assert(not w.removeButton or not w.removeButton:IsShown(),'released X remains shown')
   end
  end
 end end
 assert(visible==count,'wrong visible card count')
 for i,a in ipairs(active)do for j=i+1,table.getn(active)do local b=active[j]
  assert(a:GetRight()<=b:GetLeft()or b:GetRight()<=a:GetLeft()or a:GetTop()<=b:GetBottom()or b:GetTop()<=a:GetBottom(),'overlapping card bounds')
 end end
 local g=ghost(h);assert(not g or not g:IsShown(),'drag ghost survives release/refresh')
 assert(table.getn(h.actions)==0,'live action escaped');countSelf(h);states=states+1
end
local function aim(h,target)
 h.env.GetCursorPosition=function()return (target:GetLeft()+target:GetRight())/2,(target:GetBottom()+target:GetTop())/2 end
end
local function drag(h,from,to,hover)
 local source,target=row(h,from),row(h,to);aim(h,target)
 h:fire(source,'OnEnter');h:fire(source,'OnDragStart','LeftButton')
 assert(source:GetAlpha()==0.35 and not source.moving,'production drag moved the source widget')
 assert(ghost(h)and ghost(h):IsShown(),'drag ghost missing')
 h:fire(source,'OnLeave')
 if hover then h:fire(target,'OnEnter')end
 -- Exercise the registered updater, not a replacement drag/move function.
 for _,w in ipairs(h.frames)do if w.scripts.OnUpdate and w~=h.env.ShirsRaidBuilderMainFrame and w.kind=='Frame'and w.name==nil then
  -- Only the ghost updater has no parent, no events, and is created after the ghost.
  if w.parent==nil and next(w.events)==nil then h:fire(w,'OnUpdate',0.016)end
 end end
 h:fire(source,'OnDragStop','LeftButton');stable(h)
end
local function switch(h,name)
 local main=h.env.ShirsRaidBuilderMainFrame;local selector
 for _,w in ipairs(h.frames)do if w.parent==main and w.options and w.label and w.label:GetText()==h.env.ShirsRaidBuilderDB.currentPreset then selector=w end end
 assert(selector,'real preset selector missing');h:choose(selector,name)
 assert(h.env.ShirsRaidBuilderDB.currentPreset==name,'registered profile selection failed');stable(h)
end
local function removeAndMove(h,mover,method,hover)
 local p=h:preset();local removed=p.entries[40].charName;local moved=p.entries[39].charName
 assert(removed~='Tester'and moved==(mover=='self'and'Tester'or'Ownalt'),'fixture identity was normalized before incident')
 assert(h.C.CanRemoveBoardEntry(p.entries[40]),'same-account logged-out alt treated as mandatory self')
 if method=='context'then
  h:fire(row(h,40),'OnMouseUp','RightButton');h:click(h:button(h.env.ShirsRaidBuilderContextFrame,'Remove from plan'))
 else h:click(h:button(row(h,40),'X'))end
 assert(p.entries[40].kind=='empty'and p.entries[39].charName==moved,'registered removal did not vacate40');stable(h)
 h:fire(row(h,40),'OnEnter');assert(row(h,40).quickHighlight:IsShown(),'vacated40 hover absent');h:fire(row(h,40),'OnLeave')
 drag(h,39,40,hover)
 assert(p.entries[39].kind=='empty'and p.entries[40].charName==moved,'39 to vacated40 did not persist')
 absent(h,removed);return removed,moved
end
local function reopen(h)
 local main=h.env.ShirsRaidBuilderMainFrame;main:Hide();h.env.SlashCmdList.SHIRSRAIDBUILDER('');assert(main:IsVisible(),'slash reopen failed');stable(h)
end
local function reload(h)
 local saved=assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))()
 local out=safety(boot(saved,'Tester','Shaman'));stable(out);return out
end
local read=os.getenv('SRB_LIFECYCLE_READ')
if read then
 local h=safety(boot(assert(loadfile(read))(),'Tester','Shaman'));stable(h)
 assert(h:preset().entries[39].kind=='empty'and h:preset().entries[40].charName=='Tester','fresh process lost39->40')
 absent(h,'Ownalt');switch(h,'B');switch(h,'A');reopen(h)
 print('board lifecycle fresh process: PASS');return
end
-- Keep each native backdrop attached across reuse. Rebuilding it on an
-- unchanged card can reset edge UVs without a subsequent native size change.
-- This checks production API calls, not native rendering or deferred layout.
local function backdrops(h)
 local count=0
 for kind,pool in pairs(h.C.boardPools)do for index,w in pairs(pool)do
  if kind~='header'then
   assert(w.backdropCalls==1,'native backdrop rebuilt on pooled '..kind..index..': '..tostring(w.backdropCalls)..' calls')
   count=count+1
  else assert(not w.backdropCalls,'header unexpectedly acquired a card backdrop')end
 end end
 assert(count>=40,'fixture did not construct a complete board')
 local g=ghost(h);assert(not g or g.backdropCalls==1,'drag ghost backdrop rebuilt')
end
for _,mover in ipairs({'self','alt'})do for _,shape in ipairs({'empty','sparse','mixed','full'})do
 local moving,other=mover,shape
 test('native backdrop retained after remove40 drag39->40 '..moving..' other='..other,function()
  local h=fixture(moving,other);local p=h:preset()
  local companions={copy(p.entries[2]),copy(p.entries[7])}
  local before=h.C.boardPools.entry[40].backdropCalls
  removeAndMove(h,moving,'X',true)
  local destination=row(h,40)
  print('BACKDROP_BOUNDARY '..moving..'/'..other..' entry40='..before..'->'..destination.backdropCalls)
  assert(destination.backdropCalls==1,'post-drop entry40 rebuilt its native backdrop: '..destination.backdropCalls..' calls')
  backdrops(h)
  h:fire(destination,'OnEnter');backdrops(h)
  assert(destination.backdropColor[1]==0.28 and destination.backdropColor[2]==0.22,'human hover paint missing')
  h:fire(destination,'OnLeave');stable(h);backdrops(h)
  assert(destination.backdropColor[1]==0.18 and destination.backdropColor[2]==0.14,'human leave paint missing')
  local empty=row(h,39);h:fire(empty,'OnEnter');backdrops(h)
  assert(empty.quickHighlight:IsShown(),'source empty hover missing')
  h:fire(empty,'OnLeave');stable(h);backdrops(h)
  h:fire(destination,'OnMouseUp','RightButton');backdrops(h)
  h:click(h:button(h.env.ShirsRaidBuilderContextFrame,'Close'));stable(h);backdrops(h)
  for cycle=1,8 do switch(h,'B');backdrops(h);switch(h,'A');backdrops(h)end
  for cycle=1,4 do
   h.env.RefreshComposition();stable(h);backdrops(h)
   h:click(h.C.boardPools.header[8]);stable(h);backdrops(h)
   h:click(h.C.boardPools.header[8]);stable(h);backdrops(h)
  end
  for _,move in ipairs({{40,39},{39,40},{40,36},{36,40}})do drag(h,move[1],move[2],true);backdrops(h)end
  reopen(h);backdrops(h);h=reload(h);backdrops(h)
  assert(h.C.PlannerEqual(companions[1],h:preset().entries[2])and h.C.PlannerEqual(companions[2],h:preset().entries[7]),'backdrop lifecycle changed companion payloads')
 end)
end end
for _,mover in ipairs({'self','alt'})do for _,shape in ipairs({'empty','sparse','mixed','full'})do for _,method in ipairs({'X','context'})do for _,hover in ipairs({false,true})do
 local moving,other,removal,hovered=mover,shape,method,hover
 test('remove40 then39->40 '..moving..' other='..other..' remove='..removal..' hover='..tostring(hovered),function()
  local h=fixture(moving,other);stable(h);local p=h:preset();local before={copy(p.entries[2]),copy(p.entries[7])}
  local removed,moved=removeAndMove(h,moving,removal,hovered);local frozen=dump(p)
  assert(h.C.PlannerEqual(before[1],p.entries[2])and h.C.PlannerEqual(before[2],p.entries[7]),'companion metadata changed')
  for n=1,12 do switch(h,'B');switch(h,'A');assert(dump(h:preset())==frozen,'plan switch mutated A');absent(h,removed)end
  h:fire(row(h,40),'OnEnter');h:fire(row(h,40),'OnLeave');stable(h)
  h:fire(row(h,40),'OnMouseUp','RightButton');h:click(h:button(h.env.ShirsRaidBuilderContextFrame,'Close'));stable(h)
  for n=1,8 do h.env.RefreshComposition();stable(h)end
  reopen(h);h=reload(h);assert(h:preset().entries[40].charName==moved,'reload moved human40');absent(h,removed)
 end)
end end end end

test('multiple vacated slots and both directions preserve each identity exactly once',function()
 local h=fixture('self','mixed');removeAndMove(h,'self','X',true)
 for _,pair in ipairs({{40,39},{39,40},{40,38},{38,40},{40,36},{36,40},{40,1},{1,40}})do
  drag(h,pair[1],pair[2],true);assert(countSelf(h)==pair[2],'manual move changed on repaint')
 end
 stable(h);absent(h,'Ownalt')
end)

test('plan switching during drag hides ghost and invalidates captured old callbacks',function()
 local h=fixture('self','full');removeAndMove(h,'self','X',false)
 local w=row(h,40);aim(h,row(h,39));h:fire(w,'OnDragStart','LeftButton');local stop=w.scripts.OnDragStop;local enter=w.scripts.OnEnter
 switch(h,'B');local before=dump(h:preset());stop();enter();stable(h);assert(dump(h:preset())==before,'stale A drag altered B')
 switch(h,'A');stable(h);assert(countSelf(h)==40,'cancelled drag altered A')
end)

test('collapsed group hide/reuse followed by plan switching preserves border and pool geometry',function()
 local h=fixture('self','mixed');removeAndMove(h,'self','X',true)
 for cycle=1,6 do
  h:click(h.C.boardPools.header[8]);stable(h);switch(h,'B');switch(h,'A');h:click(h.C.boardPools.header[8]);stable(h)
  h:click(h.C.boardPools.header[1]);stable(h);h:click(h.C.boardPools.header[1]);stable(h)
 end
 assert(countSelf(h)==40,'collapse changed occupancy')
end)

test('current self at40 remains protected even when another same-account alt occupies39',function()
 local h=fixture('alt','mixed');local p=h:preset();p.entries[1]={kind='empty'};p.entries[40]=human('Tester');h.env.RefreshComposition();stable(h)
 assert(not h.C.CanRemoveBoardEntry(p.entries[40]),'self40 became removable')
 assert(not pcall(function()h:button(row(h,40),'X')end),'self40 has X')
 assert(h.C.CanRemoveBoardEntry(p.entries[39]),'offline alt39 became mandatory')
end)

test('generated plan control cannot misidentify mandatory self40 as removable alt40',function()
 local h=fixture('alt','mixed',40);stable(h);local p=h:preset()
 assert(countSelf(h)==40 and not h.C.CanRemoveBoardEntry(p.entries[40]),'generated current-self placement/guard changed')
end)

test('close during active drag clears ghost and reopening restores source alpha',function()
 local h=fixture('self','sparse');removeAndMove(h,'self','X',false)
 local w=row(h,40);aim(h,row(h,39));h:fire(w,'OnDragStart','LeftButton');h.env.ShirsRaidBuilderMainFrame:Hide()
 assert(not ghost(h):IsShown(),'hidden builder retained drag ghost');h.env.SlashCmdList.SHIRSRAIDBUILDER('');stable(h)
end)

test('same-account character login retains previous human then exact remove40 move39 succeeds',function()
 local h=fixture('self','mixed');local db=copy(h.env.ShirsRaidBuilderDB);local p=db.presets.A
 for i=1,38 do p.entries[i]=normal()end
 p.entries[39]={kind='empty'};p.entries[40]=human('Ownalt','priest','healer')
 local old=safety(boot(db,'Ownalt','Priest'))
 assert(old:preset().entries[40].charName=='Ownalt','first character lost self40')
 assert(not old.C.CanRemoveBoardEntry(old:preset().entries[40]),'logged-in Ownalt is removable')
 local saved=assert(loadstring('return '..dump(old.env.ShirsRaidBuilderDB)))()
 h=safety(boot(saved,'Tester','Shaman'));stable(h);p=h:preset()
 assert(countSelf(h)==39 and p.entries[40].charName=='Ownalt','same-account character change did not yield exact incident identities')
 local companions={};for i=1,38 do companions[i]=copy(p.entries[i])end
 removeAndMove(h,'self','X',true);switch(h,'B');switch(h,'A');reopen(h);h=reload(h)
 for i=1,38 do assert(h.C.PlannerEqual(companions[i],h:preset().entries[i]),'character login/removal overwrote companion slot '..i)end
 absent(h,'Ownalt');assert(countSelf(h)==40,'corrected move lost current self')
end)

test('same-account discovery alone never inserts offline alts into companion slots',function()
 local h=fixture('alt','mixed');local p=h:preset();p.entries[39]={kind='empty'};p.entries[40]={kind='empty'}
 h.env.RefreshComposition();stable(h);local before=dump(p.entries)
 local rows=h.C.AccountReadLocal();assert(table.getn(rows)>=3,'fixture did not expose same-account discovery')
 h.env.RefreshComposition();stable(h);assert(before==dump(p.entries),'account discovery changed board occupants')
 absent(h,'Ownalt');absent(h,'Otheralt')
end)

test('explicit occupied swap preserves normal and legacy companion payloads',function()
 local h=fixture('self','mixed');removeAndMove(h,'self','X',true)
 local p=h:preset();local normalBefore=copy(p.entries[2]);local legacyBefore=copy(p.entries[7])
 drag(h,40,2,true);assert(countSelf(h)==2 and h.C.PlannerEqual(normalBefore,p.entries[40]),'normal companion was overwritten rather than swapped')
 drag(h,2,7,true);assert(countSelf(h)==7 and h.C.PlannerEqual(legacyBefore,p.entries[2]),'legacy companion was overwritten rather than swapped')
 drag(h,7,2,true);drag(h,2,40,true)
 assert(h.C.PlannerEqual(normalBefore,p.entries[2])and h.C.PlannerEqual(legacyBefore,p.entries[7]),'reverse swap lost companion metadata')
 switch(h,'B');switch(h,'A');reopen(h);stable(h)
end)

local out=os.getenv('SRB_LIFECYCLE_OUT')
if out and fail==0 then
 local h=fixture('self','mixed');removeAndMove(h,'self','X',true)
 local f=assert(io.open(out,'w'));f:write('return '..dump(h.env.ShirsRaidBuilderDB));f:close()
end
print('BOARD_LIFECYCLE_STATES='..states)
print('board plan lifecycle: '..(fail==0 and'PASS'or'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('board plan lifecycle checks failed')end
