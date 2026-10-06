dofile('../addon/ShirsRaidBuilder/ShirsRaidBuilder_Core.lua')
local C=ShirsRaidBuilderCore
local preset={entries={{kind='legacy',charName='Mageone',class='mage',role='rdps',denyList={'Fireball','Frostbolt'}}},denyRules={},setupRules={}}
local q=C.BuildQueue(preset)
assert(table.getn(q)==2,'same target denies must form one whisper')
assert(q[2].target=='Mageone-lite' and q[2].command=='deny add Fireball, Frostbolt','incorrect server deny batch grammar')
local function deny(target,ability,phase)
    return {kind='deny',chatType='WHISPER',target=target,ability=ability,phase=phase or 'role-class-final',command='deny add '..ability}
end
local input={deny('Alpha','Fireball'),deny('Beta','Fireball'),deny('Alpha','Frostbolt'),deny('Beta','Frostbolt')}
local out=C.BatchDenyQueue(input)
assert(table.getn(out)==2 and out[1].target=='Alpha' and out[2].target=='Beta')
assert(out[1].command=='deny add Fireball, Frostbolt' and out[2].command==out[1].command)
assert(input[1].command=='deny add Fireball','batching must not mutate source')
local setup={kind='setup',phase='role-class-final',target='Alpha',chatType='WHISPER',command='deny remove growl'}
out=C.BatchDenyQueue({deny('Alpha','Fireball'),setup,deny('Alpha','Frostbolt'),deny('Alpha','Blizzard','legacy-custom')})
assert(table.getn(out)==4 and out[2]==setup,'unrelated command/phase must be a barrier')
for _,bad in ipairs({'Foo, Bar','Bad\nName','|Hspell:1|h[Link]|h','table: 001','Bad;command'}) do
    out=C.BatchDenyQueue({deny('Alpha','Fireball'),deny('Alpha',bad),deny('Alpha','Frostbolt')})
    assert(table.getn(out)==3 and out[2].command=='deny add '..bad,'unsafe argument changed or merged')
end
out=C.BatchDenyQueue({deny('','Fireball'),deny('','Frostbolt')})
assert(table.getn(out)==2,'unresolved targets must retain single ability metadata')
preset.entries[1].denyList={' ',' Fireball ','fireball','Frostbolt'}
q=C.BuildQueue(preset)
assert(table.getn(q)==2 and q[2].command=='deny add Fireball, Frostbolt','normalization changed')
out=C.BatchDenyQueue({deny('Alpha',string.rep('A',120)),deny('Alpha',string.rep('B',124)),deny('Alpha','C')})
assert(string.len(out[1].command)==255 and table.getn(out)==2 and out[2].command=='deny add C','whole ability size split failed')
out=C.BatchDenyQueue({deny('Alpha','Fireball'),deny('Alpha','Fireball')})
assert(out[1].command=='deny add Fireball, Fireball','batcher added new deduplication')
local file=assert(io.open('test_individual_editor.lua','r')); local fixture=file:read('*a'); file:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local function client()
    local h=boot(nil,'Tester'); h.now=100; h.sent={}; h.requests={}
    h.env.GetTime=function() return h.now end
    h.env.SendChatMessage=function(text,route,language,target) table.insert(h.sent,{text=text,route=route,target=target}) end
    h.env.SendAddonMessage=function(prefix,text,route) table.insert(h.requests,text) end
    h:preset().entries={}; h:preset().denyRules={}; h:preset().setupRules={}
    return h
end
local function tick(h,seconds)
    h.now=h.now+seconds
    for _,w in ipairs(h.frames) do if w.kind=='Frame' and w.scripts.OnUpdate then h:fire(w,'OnUpdate',seconds) end end
end
local h=client()
h:preset().entries={{kind='legacy',charName='Mageone',class='mage',role='rdps',denyList={string.rep('A',247)}}}
h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Execute'))
assert(table.getn(h.sent)==0,'oversized singleton must stop before any send')
local reported=false
for _,font in ipairs(h.env.ShirsRaidBuilderMainFrame.fonts) do if string.find(font:GetText(),'255',1,true) then reported=true end end
assert(reported,'oversized singleton needs explicit size error')
h=client()
h:preset().entries={{kind='legacy',charName='Mageone',class='mage',role='rdps',denyList={'Fireball','Frostbolt'}}}
h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Preview'))
assert(table.getn(h.sent)==0,'Preview sent commands')
local preview=false
for _,message in ipairs(h.messages) do if string.find(message,'deny add Fireball, Frostbolt',1,true) then preview=true end end
assert(preview,'known target Preview omitted exact batch')
h=client()
h:preset().denyRules={{class='mage',role='all',abilities={'Fireball','Frostbolt'}}}
h.env.GetNumPartyMembers=function() return 2 end
h.env.UnitName=function(unit) if unit=='player' then return 'Tester' elseif unit=='party1' then return 'Alpha' elseif unit=='party2' then return 'Beta' end end
h.C.latestCompanionList={{name='Alpha',class='mage',role='rdps'},{name='Beta',class='mage',role='rdps'}}
h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Execute'))
assert(table.getn(h.sent)==0,'unresolved group sent before expansion')
tick(h,0.1)
assert(table.getn(h.sent)==1 and h.sent[1].target=='Alpha' and h.sent[1].text=='deny add Fireball, Frostbolt','live expansion did not batch per target')
tick(h,0.1)
assert(table.getn(h.sent)==1,'batch bypassed nod wait')
for _,w in ipairs(h.frames) do
    if w.events.CHAT_MSG_TEXT_EMOTE then h.env.event='CHAT_MSG_TEXT_EMOTE'; h.env.arg2='Alpha'; h:fire(w,'OnEvent','Alpha nods at you.') end
end
tick(h,0.1); tick(h,0.8)
assert(table.getn(h.sent)==2 and h.sent[2].target=='Beta' and h.sent[2].text=='deny add Fireball, Frostbolt','paced next target batch missing')
h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Stop')); tick(h,10)
assert(table.getn(h.sent)==2,'Stop sent more commands')
print("Shir's Raid Builder deny batch tests: PASS")
