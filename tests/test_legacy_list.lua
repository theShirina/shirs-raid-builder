-- Production UI callbacks under Lua 5.0.3; no native hit-test or server proof.
local file=assert(io.open('test_individual_editor.lua','r'))
local fixture=file:read('*a'); file:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local failures,passes=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passes=passes+1; print('PASS '..name)
    else failures=failures+1; print('FAIL '..name..': '..tostring(err)) end
end
local names={'Nameaa','Nameab','Nameac','Namead','Nameae','Nameaf','Nameag','Nameah','Nameai','Nameaj','Nameak','Nameal'}
local function open(count)
    local saved={presets={},inviteCharacters={}}
    for i=1,count do saved.inviteCharacters[names[i]]={name=names[i],class='mage',level=60,tier='t1'} end
    local h=boot(saved)
    local methods=getmetatable(h.frames[1]).__index
    function methods:SetTextColor(r,g,b) self.color={r,g,b} end
    function methods:EnableMouseWheel(v) self.wheel=v end
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Add Legacy'))
    local f=h.env.ShirsRaidBuilderAddLegacy
    f.nameInput:SetText('Name')
    return h,f,h.env.ShirsRaidBuilderLegacyNameMenu
end
local function list(menu)
    assert(menu and menu:IsVisible(),'list missing')
    assert(menu.listScroll,'legacy list has no scroll model')
    return menu.listScroll
end

test('one through five names retain compact height and no scrollbar; six shows it',function()
    for count=1,6 do
        local h,f,menu=open(count); local s=list(menu)
        assert(menu:GetHeight()==math.min(count,5)*20+8,'menu grows beyond five rows')
        assert(s.viewport:GetHeight()==math.min(count,5)*20,'viewport exceeds menu')
        assert((s.track:IsVisible() and true or false)==(count>5),'wrong scrollbar threshold')
        assert(table.getn(s.items)==count,'matches were truncated')
        for i=1,5 do assert((s.rows[i]:IsVisible() and true or false)==(i<=count)) end
    end
end)
test('wheel on menu viewport row track and thumb reaches all names and clamps',function()
    local h,f,menu=open(12); local s=list(menu)
    for _,w in ipairs({menu,s.viewport,s.rows[1],s.track,s.thumb}) do
        assert(w.wheel,'mouse wheel not enabled')
        s.offset=0; s.Paint()
        for i=1,20 do h:fire(w,'OnMouseWheel',-1) end
        assert(s.offset==7 and s.rows[5].text:GetText()=='Nameal','last name unreachable')
        for i=1,20 do h:fire(w,'OnMouseWheel',1) end
        assert(s.offset==0 and s.rows[1].text:GetText()=='Nameaa')
    end
end)
test('page and drag use real callbacks then selection uses rebound name',function()
    local h,f,menu=open(12); local s=list(menu)
    h.env.GetCursorPosition=function() return 100,0 end
    h:click(s.track); assert(s.offset==5,'track did not page down')
    h.env.GetCursorPosition=function() return 100,1000 end
    h:click(s.track); assert(s.offset==0,'track did not page up')
    h.env.GetCursorPosition=function() return 100,0 end
    h:fire(s.thumb,'OnMouseDown','LeftButton'); h:fire(s.thumb,'OnUpdate',0.1)
    assert(s.offset==7,'drag did not reach bottom')
    h:fire(s.thumb,'OnMouseUp','LeftButton'); assert(not s.dragging)
    h:click(s.rows[5]); assert(f.nameInput:GetText()=='Nameal','stale row identity selected')
    assert(not menu:IsVisible())
    assert(f.classButton.label:GetText()=='Mage','selection lost class reuse')
end)
test('query shrink reset close and reopen cannot retain offset or drag',function()
    local h,f,menu=open(12); local s=list(menu)
    h:fire(s.viewport,'OnMouseWheel',-7); assert(s.offset==7)
    h:fire(s.thumb,'OnMouseDown','LeftButton')
    f.nameInput:SetText('Namea') -- same matches but a new query resets offset.
    assert(s.offset==0 and not s.dragging)
    f.nameInput:SetText('Nameal'); assert(not menu:IsVisible(),'exact name not excluded')
    f.nameInput:SetText('NoMatch'); assert(not menu:IsVisible())
    f.nameInput:SetText(''); assert(menu:IsVisible(),'legacy empty-query behavior changed')
    assert(s.offset==0)
    h:fire(s.thumb,'OnMouseDown','LeftButton'); h.C.HideLegacyNameSuggestions()
    assert(not s.dragging and not menu:IsVisible())
    f.nameInput:SetFocus(); assert(menu:IsVisible() and s.offset==0)
    assert(h.C.DenyListNeedsScrollbar(5),'existing deny threshold changed')
end)

test('shared deny scroll factory retains the existing five-item threshold',function()
    local h=open(6)
    local host=h.env.CreateFrame('Frame',nil,h.env.UIParent)
    local s=h.C.EnsureDenyListScroll(host,{width=150,rowHeight=20,x=0,y=0,
        createRow=function(parent) return h.env.CreateFrame('Button',nil,parent) end,
        bindRow=function() end})
    s.items={'a','b','c','d'}; s.Paint(); assert(not s.track:IsVisible())
    table.insert(s.items,'e'); s.Paint(); assert(s.track:IsVisible())
end)

local function snapshot(value)
    if type(value)~='table' then return type(value)..':'..tostring(value) end
    local parts={}
    for k,v in pairs(value) do table.insert(parts,snapshot(k)..'='..snapshot(v)) end
    table.sort(parts); return '{'..table.concat(parts,',')..'}'
end
local function color(row,expected)
    assert(row.text.color,'text colour not recorded')
    for i=1,3 do assert(row.text.color[i]==expected[i],'wrong name colour') end
end
local colors={warrior={0.78,0.61,0.43},paladin={0.96,0.55,0.73},hunter={0.67,0.83,0.45},
    rogue={1,0.96,0.41},priest={1,1,1},shaman={0,0.44,0.87},mage={0.41,0.80,0.94},
    warlock={0.58,0.51,0.79},druid={1,0.49,0.04}}
for class,rgb in pairs(colors) do
    local key,expected=class,rgb
    test('remembered class colour remains on hover and scroll: '..key,function()
        local h,f,menu=open(12); local s=list(menu); local db=h.env.ShirsRaidBuilderDB
        db.legacyCharacters={nameaa=key,nameal=key}; db.legacyCharacterRoles={nameaa='rdps'}
        local before=snapshot(db)
        f.nameInput:SetText('Namea')
        color(s.rows[1],expected)
        h:fire(s.rows[1],'OnEnter'); color(s.rows[1],expected)
        h:fire(s.rows[1],'OnLeave'); color(s.rows[1],expected)
        h:fire(s.track,'OnMouseWheel',-7); color(s.rows[5],expected)
        assert(snapshot(db)==before,'rendering mutated saved data')
    end)
end
test('invite/generated class and older entry use read-only lookup; invalid class uses normal text',function()
    local h,f,menu=open(6); local s=list(menu); local db=h.env.ShirsRaidBuilderDB
    db.legacyCharacters={}; db.inviteCharacters.Nameaa.class='Druid'
    f.nameInput:SetText('Namea'); color(s.rows[1],colors.druid)
    db.inviteCharacters.Nameaa.class=nil
    db.presets.Old={entries={{kind='legacy',charName='NAMEAA',class='priest',role='healer'}}}
    local before=snapshot(db); f.nameInput:SetText('Nam'); color(s.rows[1],colors.priest)
    assert(snapshot(db)==before)
    db.presets.Old=nil
    for _,bad in ipairs({false,12,{},'monk','Mage',' mage '}) do
        db.legacyCharacters.nameaa=bad
        local beforeBad=snapshot(db)
        f.nameInput:SetText('Name'); f.nameInput:SetText('Nam')
        color(s.rows[1],{0.92,0.95,1})
        assert(snapshot(db)==beforeBad,'invalid class was repaired during rendering')
    end
    db.legacyCharacters=nil
    f.nameInput:SetText('Name'); color(s.rows[1],{0.92,0.95,1})
end)

test('current legacy identity is absent from suggestions',function()
    local h,f,menu=open(6)
    h:preset().entries[35]={kind='legacy',sourceName='Nameaa',charName='Nameaa-lite',class='warrior',role='mdps'}
    f.nameInput:SetText('Nam')
    for _,name in ipairs(list(menu).items) do assert(name~='Nameaa','already-added legacy remains selectable') end
    assert(table.getn(list(menu).items)==5)
end)

local function contains(menu,name)
    if not menu or not menu:IsVisible() then return false end
    for _,value in ipairs(menu.listScroll.items) do if value==name then return true end end
    return false
end
test('case-insensitive source and old names filter without rewriting duplicates or saved data',function()
    local h,f,menu=open(6)
    local entries=h:preset().entries
    entries[33]={kind='legacy',sourceName='NAMEAA',charName='Different',whisperName='Nameab',class='warrior',role='tank'}
    entries[34]={kind='legacy',charName='nAmEaC',class='mage',role='rdps'}
    entries[35]={kind='legacy',sourceName='Nameaa',charName='Nameaa',class='priest',role='healer'}
    local before=snapshot(h.env.ShirsRaidBuilderDB)
    f.nameInput:SetText('Nam')
    assert(not contains(menu,'Nameaa') and not contains(menu,'Nameac'))
    assert(contains(menu,'Nameab'),'whisper target used as identity')
    assert(snapshot(h.env.ShirsRaidBuilderDB)==before,'filter rewrites saved data')
end)
test('distinct names sharing a whisper suffix remain selectable',function()
    local h,f,menu=open(6)
    local db=h.env.ShirsRaidBuilderDB
    db.inviteCharacters.Longname={name='Longname',class='mage'}
    db.inviteCharacters.Longnamer={name='Longnamer',class='mage'}
    f.nameInput:SetText('Longname'); h:click(f.addButton)
    f.nameInput:SetText('Long')
    assert(not contains(menu,'Longname') and contains(menu,'Longnamer'))
    assert(h.C.NormalizeLegacyName('Longname')==h.C.NormalizeLegacyName('Longnamer'))
end)
test('add refreshes hidden matches and reopen refreshes without another keystroke',function()
    local h,f,menu=open(6)
    h:click(list(menu).rows[1]); h:click(f.addButton)
    assert(f.nameInput:GetText()=='' and not menu:IsVisible() and f:IsVisible())
    for _,name in ipairs(menu.listScroll.items) do assert(name~='Nameaa','Add leaves stale matches') end
    h:click(f.cancelButton)
    h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Add Legacy'))
    assert(menu:IsVisible(),'reopen does not refresh the list')
    assert(not contains(menu,'Nameaa') and contains(menu,'Nameab'))
end)
test('remove callback immediately restores selectable name and scrollbar',function()
    local h,f,menu=open(6)
    f.nameInput:SetText('Nameaa'); h:click(f.addButton)
    f.nameInput:SetText('Name'); assert(not contains(menu,'Nameaa'))
    assert(not list(menu).track:IsVisible())
    local remove
    for _,w in ipairs(h.frames) do
        if w.kind=='Button' and w:IsVisible() and w.fonts[1] and string.find(w.fonts[1]:GetText(),'Nameaa-lite',1,true) then
            remove=h:button(w,'X')
        end
    end
    assert(remove,'composition remove button missing'); h:click(remove)
    assert(contains(menu,'Nameaa'),'removed name stays hidden')
    assert(list(menu).track:IsVisible(),'restored sixth name has no scrollbar')
    color(list(menu).rows[1],colors.mage)
end)
test('profile switch refreshes visible list with current legacy entries only',function()
    local h,f,menu=open(6)
    local db=h.env.ShirsRaidBuilderDB
    db.presets.Other={entries={{kind='legacy',charName='Nameaa',class='mage',role='rdps'},
        {kind='normal',charName='Nameab',account='Nameab',class='mage',role='rdps'}}}
    local current=db.currentPreset
    f.nameInput:SetText('Nam')
    assert(contains(menu,'Nameaa'),'other profile hides current suggestion')
    local selector=h:button(h.env.ShirsRaidBuilderMainFrame,current)
    selector.options={current,'Other'}
    h:choose(selector,'Other')
    assert(not contains(menu,'Nameaa'),'switch leaves previous profile matches')
    assert(contains(menu,'Nameab'),'normal hire hides legacy suggestion')
    h:choose(selector,current)
    assert(contains(menu,'Nameaa'),'switch back does not restore name')
end)
test('all matching names added uses existing hidden empty behavior',function()
    local h,f,menu=open(6)
    for i=1,6 do h:preset().entries[30+i]={kind='legacy',sourceName=names[i],class='mage',role='rdps'} end
    f.nameInput:SetText('Nam')
    assert(not menu:IsVisible(),'empty filtered list remains visible')
end)

print('Legacy list tests: '..passes..' PASS, '..failures..' FAIL')
assert(failures==0,'legacy list regression failures')
print("Shir's Raid Builder legacy list tests: PASS")
