-- Sources fill fourteen rows down before wrapping right. Registered handlers under strict
-- Vanilla widget types; synthetic geometry, not proof of native pixels.
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
local ROWS,PITCH,COLUMN=14,26,412; assert(ROWS==10+4,'requested four additional rows')
local function name(prefix,i) return prefix..string.char(65+math.floor((i-1)/26))..string.char(97+math.mod(i-1,26)) end
-- Local names sort as Aaa.., so the current account stays first without relying on luck.
local function saved(n)
    local db={syncAccountId='5555555555555555',currentPreset='Default',presets={Default={entries={{kind='player',charName='Aaplayer',class='warrior',role='tank'}},denyRules={},setupRules={}}},inviteCharacters={},legacyCharacters={},legacyCharacterRoles={}}
    local names={'Aaplayer'}; for i=2,n do table.insert(names,name('Loc',i)) end
    for _,nm in ipairs(names) do
        db.inviteCharacters[nm]={name=nm,level=60,dungeonLicense='t5d',raidLicense='t5r',faction='Alliance'}
        db.legacyCharacters[string.lower(nm)]='shaman'; db.legacyCharacterRoles[string.lower(nm)]='healer'
    end
    return db
end
local function start(db,links)
    local h=boot(db,'Aaplayer'); local C=h.C
    for _,l in ipairs(links or {}) do
        local link=C.PeerNew('Aaplayer',l.peer,'FixtureRealm'); link.phase='linked'; assert(C.LinkSave(db.peerLinks,link,true))
        local snap={accountId=l.id,source=string.lower(l.peer),realm='FixtureRealm',received=1800000000,observed=1800000000,authoritative=false,entries={}}
        for i=1,l.count do table.insert(snap.entries,{name=name(l.prefix,i),level=60,dungeonLicense='t3d',raidLicense='t4r',faction='Alliance',observed=1800000000}) end
        db.peerSnapshots['FixtureRealm;'..string.lower(l.peer)]=snap
    end
    h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn)
    local p=C.plannerFrame; assert(p:IsVisible())
    function h:row(nm) for _,r in ipairs(p.sourceRows) do if r.source and r.source.name==nm then return r end end; error('missing source '..nm) end
    function h:reopen() C.ClosePlanner(); self:click(self.env.ShirsRaidBuilderMainFrame.plannerBtn); return C.plannerFrame end
    return h,p
end
local function cell(row) return row.point[4],-row.point[5] end
-- Every visible child of the list must be a laid-out source row: no stray header or
-- overlap, nothing outside the scroll child, and every control reachable inside its row.
local function geometry(p)
    local boxes,n={},0
    for _,row in ipairs(p.sourceRows) do
        if row.source then
            n=n+1; assert(row:IsShown(),'laid-out source hidden')
            local x,y=cell(row); local w,h=row:GetWidth(),row:GetHeight()
            assert(x>=0 and x+w<=p.sourceContent:GetWidth(),'source clipped horizontally: '..row.source.name)
            assert(y>=0 and y+h<=p.sourceContent:GetHeight(),'source below list extent: '..row.source.name)
            for _,b in ipairs(boxes) do assert(x>=b.x+b.w or b.x>=x+w or y>=b.y+b.h or b.y>=y+h,'source rows overlap: '..row.source.name..' / '..b.name) end
            table.insert(boxes,{x=x,y=y,w=w,h=h,name=row.source.name})
            for _,c in ipairs({row.normalCheck,row.tierButton,row.legacyCheck,row.roleButton}) do
                local cx,cy=c.point[4],-c.point[5]
                assert(c:IsVisible() and cx>=0 and cx+c:GetWidth()<=w and cy>=0 and cy+c:GetHeight()<=h,'control hidden or clipped')
            end
        else assert(not row:IsShown(),'unused source row still shown') end
    end
    assert(n==table.getn(p.sources),'laid-out rows differ from source count')
    return n
end
local function strayChildren(h,p)
    for _,w in ipairs(h.frames) do
        if w.parent==p.sourceContent and w:IsShown() then
            local isRow=false; for _,r in ipairs(p.sourceRows) do if r==w then isRow=true end end
            assert(isRow,'non-row element inside the source list could cover rows')
        end
    end
end
local function bounds(p)
    local bottom=0
    for _,r in ipairs(p.sourceRows) do if r.source then local _,y=cell(r); if y+r:GetHeight()>bottom then bottom=y+r:GetHeight() end end end
    local view=p.sourceScroll:GetHeight()
    assert(p.sourceContent:GetHeight()==math.max(view,bottom),'list extent does not match laid-out rows')
    assert(p.sourceMax==math.max(0,p.sourceContent:GetHeight()-view),'scroll range wrong')
    if p.sourceMax>0 then assert(p.sourceSlider:IsShown(),'overflow hidden without scrollbar') else assert(not p.sourceSlider:IsShown(),'needless scrollbar') end
    assert(p.sourceScroll:GetHeight()<=p.panels.sources:GetHeight() and -p.sourceSummary.point[5]>=view,'summary overlaps the list')
    assert(not p.nextSources and not p.previousSources and not p.sourcePage,'paging returned')
    return bottom
end
local function expectGrid(p,count)
    for i=1,math.min(count,2*ROWS) do
        local x,y=cell(p.sourceRows[i])
        local col=math.floor((i-1)/ROWS); local line=math.mod(i-1,ROWS)
        assert(x==col*COLUMN and y==line*PITCH,'source '..i..' at '..x..','..y..' expected '..(col*COLUMN)..','..(line*PITCH))
    end
end
local function accountsContiguous(p)
    local seen,last={},nil
    for _,s in ipairs(p.sources) do
        local id=s.localSource and 'local' or tostring(s.accountId)
        if id~=last then assert(not seen[id],'account block split: '..id); seen[id]=true; last=id end
    end
    assert(p.sources[1].localSource,'current account not first')
end

test('short single account stays in one column from the top',function()
    local h,p=start(saved(3)); assert(geometry(p)==3); expectGrid(p,3); bounds(p); strayChildren(h,p)
    for i=1,3 do assert(cell(p.sourceRows[i])==0) end
end)
for _,count in ipairs({10,13,14,15,28,29}) do
 test('fourteen-row boundary '..count..' sources, fourteen fit without changing frame height',function()
    local h,p=start(saved(count)); assert(geometry(p)==count); expectGrid(p,count); bounds(p); strayChildren(h,p)
    assert(p.sourceScroll:GetHeight()==366,'viewport height changed')
    for i=1,math.min(count,14) do assert(cell(p.sourceRows[i])==0,'wrapped before fourteen rows') end
    if count>=15 then local x,y=cell(p.sourceRows[15]); assert(x==COLUMN and y==0,'15th must wrap right at top') end
    if count>=28 then local x,y=cell(p.sourceRows[28]); assert(x==COLUMN and y==13*PITCH,'28th must finish right column') end
    if count>=29 then local x,y=cell(p.sourceRows[29]); assert(x==0 and y==14*PITCH+8,'29th must start next band') end
    if count<=28 then assert(p.sourceMax==0,'fourteen rows should fit the unchanged viewport') else assert(p.sourceMax==30,'first overflow must stay reachable') end
 end)
end
test('multiple accounts keep current-account-first contiguous blocks in column-major reading order',function()
    local h,p=start(saved(7),{{peer='Peerone',id='2222222222222222',prefix='Rmo',count=3},{peer='Peertwo',id='3333333333333333',prefix='Rmt',count=6}})
    assert(table.getn(p.sources)==16); accountsContiguous(p); assert(geometry(p)==16); expectGrid(p,16); bounds(p); strayChildren(h,p)
    for i,s in ipairs(p.sources) do assert(p.sourceRows[i].source==s,'cell order differs from source order') end
    local before=dump(p.sources); p=h:reopen(); accountsContiguous(p); assert(dump(p.sources)==before,'account order unstable on reopen')
end)
test('manual choices on a wrapped source survive repaint, reopen and reload',function()
    local h,p=start(saved(18)); local row=p.sourceRows[17]; local nm=row.source.name; local key=row.source.key
    assert(cell(row)==COLUMN,'fixture source is not in the wrapped column')
    row.normalCheck:SetChecked(1); h:fire(row.normalCheck,'OnClick'); h:choose(row.tierButton,'t2r')
    row.legacyCheck:SetChecked(1); h:fire(row.legacyCheck,'OnClick'); h:choose(row.roleButton,'mdps')
    local expected=dump(p.request.sources[key])
    for _=1,3 do h.C.PlannerPaintSources() end
    assert(dump(p.request.sources[key])==expected and h:row(nm)==p.sourceRows[17])
    p=h:reopen(); assert(dump(p.request.sources[key])==expected and h:row(nm).roleButton.label:GetText()=='mdps')
    local db=assert(loadstring('return '..dump(h.env.ShirsRaidBuilderDB)))()
    h,p=start(db); row=h:row(nm); assert(dump(p.request.sources[key])==expected)
    assert(row.normalCheck:GetChecked() and row.legacyCheck:GetChecked() and row.tierButton.label:GetText()=='t2r')
    assert(cell(row)==COLUMN); geometry(p)
end)
test('repeated rendering reuses rows, keeps positions and hides rows after the roster shrinks',function()
    local h,p=start(saved(21)); local snapshot={}
    for i=1,21 do local x,y=cell(p.sourceRows[i]); snapshot[i]=x..','..y end
    local made=table.getn(p.sourceRows)
    for _=1,5 do h.C.PlannerPaintSources() end
    assert(table.getn(p.sourceRows)==made,'repaint created extra rows')
    for i=1,21 do local x,y=cell(p.sourceRows[i]); assert(snapshot[i]==x..','..y,'repaint moved source '..i) end
    local keep={}; for i=1,12 do keep[i]=p.sources[i] end; p.sources=keep; h.C.PlannerPaintSources()
    assert(geometry(p)==12); expectGrid(p,12); bounds(p)
end)
test('list height is bounded: twenty-eight fit, overflow scrolls continuously to the last source',function()
    local h,p=start(saved(28)); local bottom=bounds(p); assert(bottom<=p.sourceScroll:GetHeight() and p.sourceMax==0)
    h,p=start(saved(42)); assert(geometry(p)==42); expectGrid(p,42); bottom=bounds(p); assert(p.sourceMax>0)
    h:fire(p.sourceScroll,'OnMouseWheel',-1); assert(p.sourceScroll:GetVerticalScroll()>0)
    p.sourceSlider:SetValue(p.sourceMax); local last=p.sourceRows[42]; local _,y=cell(last)
    assert(y+last:GetHeight()<=p.sourceScroll:GetVerticalScroll()+p.sourceScroll:GetHeight(),'last source unreachable')
    last.normalCheck:SetChecked(1); h:fire(last.normalCheck,'OnClick'); assert(p.request.sources[last.source.key].selected)
end)
print("Shir's Raid Builder sources wrap tests: "..(fail==0 and 'PASS' or 'FAIL')..' ('..pass..' passed, '..fail..' failed)')
if fail>0 then error('sources wrap regressions failed') end
