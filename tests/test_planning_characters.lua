local f=assert(io.open('test_individual_editor.lua','r')); local fixture=f:read('*a'); f:close()
local boundary=assert(string.find(fixture,'\nlocal failures, passes=',1,true))
local boot=assert(loadstring(string.sub(fixture,1,boundary-1)..'\nreturn boot'))()
local h=boot(nil,'Alice'); local C=h.C; local db=h.env.ShirsRaidBuilderDB
local s=C.PeerNew('Alice','Bob','FixtureRealm'); s.phase='linked'; C.LinkSave(db.peerLinks,s,true)
local rows={}
for i=1,12 do table.insert(rows,{name='Alt'..string.char(64+i),level=60,dungeonLicense='t2d',raidLicense='t2r',observed=1800000000}) end
db.peerSnapshots={['FixtureRealm;bob']={accountId='1234567890123456',source='bob',realm='FixtureRealm',received=1800000000,observed=1800000000,entries=rows,authoritative=false}}
assert(type(C.RememberedHireNames)=='function','remembered planning roster helper missing')
local names=C.RememberedHireNames(db,'Alice','FixtureRealm')
assert(table.getn(names)==12 and names[12]=='AltL')
assert(table.getn(C.RememberedHireNames(db,'Alice','OtherRealm'))==0,'realm leaked')
C.LinkForget(db.peerLinks,'Alice','Bob','FixtureRealm',true)
assert(table.getn(C.RememberedHireNames(db,'Alice','FixtureRealm'))==0,'revoked roster selectable')
C.LinkSave(db.peerLinks,s,true)
-- Fresh boot simulates offline/reload: saved roster, no live session; selectors send nothing.
h=boot(db,'Alice'); C=h.C
h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Add Normal'))
local normal=h.env.ShirsRaidBuilderAddNormal
h:click(normal.characterButton)
local menu=h.env.ShirsRaidBuilderCharacterChoices
assert(menu and menu:IsShown() and menu:GetHeight()==108,'normal five-row dropdown missing')
local scroll=menu.listScroll
assert(scroll and scroll.track:IsShown() and scroll.thumb.wheel)
h:fire(scroll.rows[1],'OnMouseWheel',-1)
assert(scroll.offset==1 and scroll.rows[1].wheel,'normal row wheel missing')
local function chooseLast()
 local index; for i,name in ipairs(scroll.items) do if name=='AltL' then index=i end end
 assert(index); scroll.offset=index-5; scroll.Paint(); h:click(scroll.rows[5])
end
chooseLast()
assert(normal.characterButton.label:GetText()=='AltL','normal selection failed')
-- A linked account's character offers only the tiers its snapshot lists (dungeon T2,
-- raid T2 here), and Add Normal starts on its highest.
assert(table.concat(normal.tierButton.options,',')=='t0d,t1d,t2d,t1r,t2r','linked character tiers: '..table.concat(normal.tierButton.options,','))
assert(normal.tierButton.label:GetText()=='t2r','tier did not start on the highest: '..normal.tierButton.label:GetText())
h:click(h:button(h.env.ShirsRaidBuilderMainFrame,'Add Legacy'))
local legacy=h.env.ShirsRaidBuilderAddLegacy
assert(legacy.characterButton,'legacy visible dropdown missing')
h:click(legacy.characterButton)
assert(menu:IsShown() and menu.listScroll.track:IsShown() and menu:GetHeight()==108)
scroll=menu.listScroll; chooseLast()
assert(legacy.nameInput:GetText()=='AltL','legacy selection failed')
assert(not menu:IsShown(),'menu stayed open')
-- Add Legacy: the open name list sits clear of the other controls and draws above them.
-- Panel units from the recorded anchors (TOPLEFT/BOTTOMLEFT only), y up: left,top,right,bottom.
do
 local f=legacy
 f.nameInput:SetText(''); C.RefreshLegacyNameSuggestions(f.nameInput)
 local list=h.env.ShirsRaidBuilderLegacyNameMenu
 assert(list and list:IsShown() and list:GetHeight()==108,'legacy name list not open')
 local function box(w)
  if w==f then return 0,0,f:GetWidth(),-f:GetHeight() end
  local p=assert(w.point,'unanchored panel child')
  local l,t,r,b=box(p[2] or w.parent)
  local x=l+(p[4] or 0); local y=(string.find(p[3] or p[1],'^BOTTOM') and b or t)+(p[5] or 0)
  local width,height=w:GetWidth(),w:GetHeight()
  if w.kind=='FontString' then width=w:GetStringWidth(); height=12 end
  if string.find(p[1],'^BOTTOM') then return x,y+height,x+width,y end
  return x,y,x+width,y-height
 end
 local function clear(a,c)
  local al,at,ar,ab=box(a); local cl,ct,cr,cb=box(c)
  return ar<=cl or cr<=al or at<=cb or ct<=ab
 end
 local caption
 for _,font in ipairs(f.fonts) do if font:GetText()=='Remembered characters' then caption=font end end
 assert(caption,'remembered caption missing')
 assert(clear(list,f.characterButton),'legacy name list covers the remembered characters dropdown')
 assert(clear(list,caption),'legacy name list covers the remembered characters caption')
 assert(list:GetFrameLevel()>f.characterButton:GetFrameLevel(),'a panel control draws through the open legacy name list')
 local _,_,right=box(f.characterButton)
 assert(right<=f:GetWidth(),'remembered characters dropdown leaves the panel')
 C.HideLegacyNameSuggestions()
end
-- Own account rows: a level reading other than 60 (loading screen or logout) never deletes a
-- level-60 character, and the saved server list refills missing rows with real licences.
do
 local db={currentPreset='Default',presets={Default={entries={},denyRules={},setupRules={}}},
  inviteCharacters={Ownmain={name='Ownmain',level=60,raidLicense='t4r',dungeonLicense='none'},
   Ownalt={name='Ownalt',level=60,raidLicense='t5r',dungeonLicense='none'}},
  localAccountRows={FixtureRealm={{name='Ownmain',level=60,raidLicense='t4r',dungeonLicense='none',observed=1799999000},
   {name='Ownalt',level=60,raidLicense='t5r',dungeonLicense='none',observed=1799999000}}}}
 local o=boot(db,'Ownmain'); local level=0
 o.env.UnitLevel=function() return level end
 local function licences(rows)
  local out={}; for _,r in ipairs(rows or db.localAccountRows.FixtureRealm) do out[r.name]=r.raidLicense end; return out
 end
 o.C.AccountReadLocal()
 local seen=licences()
 assert(seen.Ownmain=='t4r' and seen.Ownalt=='t5r','a level-0 reading deleted the current character')
 o.C.AccountReadLocal({{name='Ownmain',level=60,raidLicense='t4r',dungeonLicense='none'},{name='Ownalt',level=60,raidLicense='t5r',dungeonLicense='none'}})
 seen=licences()
 assert(seen.Ownmain=='t4r' and seen.Ownalt=='t5r','a server list read at a level-0 moment deleted the current character')
 level=60
 db.localAccountRows.FixtureRealm={{name='Ownalt',level=60,raidLicense='t5r',dungeonLicense='none',observed=1799999000}}
 seen=licences(o.C.AccountReadLocal())
 assert(seen.Ownmain=='t4r','current character came back without its saved licence: '..tostring(seen.Ownmain))
 db.localAccountRows.FixtureRealm={{name='Ownmain',level=60,raidLicense='t4r',dungeonLicense='none',observed=1799999000}}
 seen=licences(o.C.AccountReadLocal())
 assert(seen.Ownalt=='t5r','missing own alt not refilled from the saved server list')
 o.env.RefreshAccountPanel()
 local tier
 for _,row in ipairs(o.env.ShirsRaidBuilderMainFrame.accountRows) do if row.model and row.model.name=='Ownmain' then tier=row.model.tier end end
 assert(tier=='T4R','sidebar hides the current character licence: '..tostring(tier))
end
-- A normal hire's licence tier shows on its plan card without hovering, written as the
-- sidebar writes it (T5R; the base tier reads T0 whether saved as t0 or t0d): bottom right,
-- under a compact remove button, raid tiers in the header gold and dungeon tiers in the
-- panel's light blue. The tier is always whole: its box fits its text. Roles read Tank,
-- Heal, MDPS and RDPS. A measured width runs past the drawn letters, so the class line may
-- reach 2 units into the tier's measured width; only beyond that does the class name lose
-- letters from its end, never more than it must. Card size and colours stay; legacy and
-- player cards show no tier.
do
 local function cards(t)
  local function card(prefix)
   for _,w in ipairs(t.frames) do
    if w.kind=='Button' and w:IsVisible() and w.scripts.OnMouseUp and w.fonts[1]
     and string.sub(w.fonts[1]:GetText(),1,string.len(prefix))==prefix then return w end
   end
   error('plan card missing: '..prefix)
  end
  return card
 end
 local function remove(t,row)
  for _,w in ipairs(t.frames) do if w.kind=='Button' and w.parent==row and w.label and w.label:GetText()=='X' then return w end end
 end
 -- The class line is the class name, or its start, then the whole role; never cut by the
 -- client, within 2 units of the tier, and shortened only as far as it must be.
 local function reads(row,class,role,label)
  local line,f=row.fonts[2],row.tierText
  local text=line:GetText()
  local _,_,cut,tail=string.find(text,'^(%a+) (%a+)$')
  assert(cut and tail==role and string.len(cut)>=3 and string.sub(class,1,string.len(cut))==cut,label..' class line reads '..text)
  assert(line.width and line:GetStringWidth()<=line.width,label..' class line is cut short: '..text)
  local tier=f and f:GetStringWidth() or -2
  assert(line:GetStringWidth()+tier<=96,label..' class line runs into the tier: '..text)
  if cut~=class then
   line:SetText(string.sub(class,1,string.len(cut)+1)..' '..role)
   assert(line:GetStringWidth()+tier>96,label..' class name shortened more than needed: '..text)
   line:SetText(text)
  end
  return cut
 end
 local function tag(row,text,color,label)
  local f=row.tierText
  assert(f and f:GetText()==text,label..' tier not shown: '..tostring(f and f:GetText()))
  local c=f.textColor
  assert(c[1]==color[1] and c[2]==color[2] and c[3]==color[3],label..' tier colour')
  assert(f.point[1]=='TOPRIGHT' and f.point[4]==-3 and f.point[5]==-15,label..' tier is not bottom right')
  assert(f:GetStringWidth()<=f.width,label..' tier is cut short: box '..tostring(f.width)..' for '..f:GetStringWidth())
  assert(row.fonts[2].point[1]=='TOPLEFT' and row.fonts[2].point[4]==3,label..' class line moved')
 end
 local gold,blue={1.0,0.84,0.28},{0.75,0.88,1.0}
 local entries={[1]={kind='normal',account='Tierown',tier='t5r',class='warrior',role='mdps',spec='default',race='human',gender='male'},
  [2]={kind='normal',account='Tierown',tier='t0d',class='warlock',role='rdps',spec='default',race='human',gender='female'},
  [3]={kind='legacy',charName='Oldmage',sourceName='Oldmage',class='mage',role='rdps',denyList={}},
  [4]={kind='normal',account='Tierown',tier='t2r',class='mage',role='rdps',spec='frost',race='human',gender='female'},
  [5]={kind='normal',account='Tierown',tier='t0',class='warrior',role='mdps',spec='default',race='human',gender='male'}}
 for i=6,40 do entries[i]={kind='empty'} end
 -- The fixture's fonts are fixed pitch, 7 units a letter, so the warrior and warlock lines
 -- must shorten here; the mage line fits whole.
 local t=boot({currentPreset='Default',presets={Default={entries=entries,denyRules={},setupRules={}}}},'Tierlead')
 local card=cards(t)
 local warrior,warlock,legacy,mage,base,player=card('1 Tierown'),card('2 Tierown'),card('3 '),card('4 Tierown'),card('5 Tierown'),card('6 Tierlead')
 for _,row in ipairs({warrior,warlock,legacy,mage}) do
  assert(row.width==100 and row.height==28,'card size changed')
  local x=remove(t,row)
  assert(x and x.width==16 and x.height==12 and x.point[1]=='TOPLEFT' and x.point[4]==82 and x.point[5]==-3,'remove button is not the compact top-right square')
 end
 tag(warrior,'T5R',gold,'raid'); tag(warlock,'T0',blue,'base t0d'); tag(mage,'T2R',gold,'whole'); tag(base,'T0',blue,'base t0')
 assert(reads(warrior,'Warrior','MDPS','warrior')=='Warri','warrior line in the fixed-pitch fixture')
 assert(reads(warlock,'Warlock','RDPS','warlock')=='Warloc','warlock line in the fixed-pitch fixture')
 assert(reads(mage,'Mage','RDPS','mage')=='Mage' and reads(legacy,'Mage','RDPS','legacy')=='Mage','a line that fits was shortened')
 assert(not legacy.tierText and not player.tierText,'legacy or player card shows a tier')
 -- The dragged card reads the same as the card.
 t:fire(warrior,'OnDragStart')
 local ghost
 for _,w in ipairs(t.frames) do if w.kind=='Frame' and w.strata=='TOOLTIP' and w.width==100 and w.height==28 and w.line2 then ghost=w end end
 assert(ghost and ghost.line2:GetText()==warrior.fonts[2]:GetText() and ghost.tier:GetText()=='T5R'
  and ghost.tier:GetStringWidth()<=ghost.tier.width and ghost.line2:GetStringWidth()+ghost.tier:GetStringWidth()<=96,'drag ghost line or tier differs from the card')
 assert(t.C.TierLabel('t0')=='T0' and t.C.TierLabel('t0d')=='T0' and t.C.TierLabel('t1d')=='T1D' and t.C.TierLabel('t5r')=='T5R'
  and t.C.TierLabel('bad')=='' and t.C.TierLabel(nil)=='','tier labels')
 -- Letter widths near the game font's on 100-unit cards, where a strict fit cut the "r"
 -- from "Warrior MDPS" beside T0D and the "n" from "Paladin MDPS" beside T1R with room
 -- to spare. The tier is a size smaller. Each of these lines must fit whole.
 local real={entries={},denyRules={},setupRules={}}
 local rows={{'warrior','mdps','t0d'},{'warrior','mdps','t5r'},{'paladin','mdps','t1r'},{'warlock','rdps','t5r'},{'mage','rdps','t1r'}}
 for i=1,40 do real.entries[i]={kind='empty'} end
 for i,r in ipairs(rows) do real.entries[i]={kind='normal',account='Realown',class=r[1],role=r[2],tier=r[3],spec='default',race='human',gender='male'} end
 local u=boot({currentPreset='Default',presets={Default=real}},'Reallead')
 local widths={W=10.5,a=6.0,r=4.4,i=3.0,o=6.4,[' ']=3.0,M=9.8,D=8.2,P=7.4,S=6.8,R=7.6,T=7.0,l=3.0,d=6.6,n=6.6,c=5.6,k=6.0,g=6.4,e=6.0,
  ['0']=6.6,['1']=6.6,['2']=6.6,['3']=6.6,['4']=6.6,['5']=6.6}
 local m=getmetatable(u.frames[1]).__index
 function m:GetFont() return 'Fonts\\FRIZQT__.TTF',self.fontSize or 10,'' end
 function m:SetFont(_,size) self.fontSize=size end
 function m:GetStringWidth()
  local w=0
  for ch in string.gfind(self.text or '','.') do w=w+(widths[ch] or 6) end
  return w*(self.fontSize or 10)/10
 end
 u.env.RefreshComposition()
 local realCard=cards(u)
 for i,r in ipairs(rows) do
  local row=realCard(i..' Realown')
  local class=string.upper(string.sub(r[1],1,1))..string.sub(r[1],2)
  assert(row.tierText and row.tierText.fontSize==9,'tier not a size below the card text')
  assert(reads(row,class,string.upper(r[2]),class..' '..r[3])==class,class..' beside '..row.tierText:GetText()..' was shortened: '..row.fonts[2]:GetText())
 end
end
-- Tiers follow the hire-from character. Add Normal lists only the tiers that character
-- holds and starts on its highest, when the panel opens and whenever another character is
-- picked; other changes keep the chosen tier. The right-click menu can move a hire to
-- another character: a tier that character lacks drops to its highest, the base tier and
-- tiers it holds stay, and a character with four hires on the board is refused.
do
 local function own(name,raid) return {name=name,level=60,raidLicense=raid,dungeonLicense='none',count=0,maxCount=4,faction='Alliance'} end
 local function row(account,tier) return {kind='normal',account=account,tier=tier,class='warrior',role='mdps',spec='default',race='human',gender='male'} end
 local entries={[1]=row('Ownmain','t5r'),[2]=row('Ownmain','t0'),[3]=row('Ownfull','t5r'),[4]=row('Ownfull','t5r'),[5]=row('Ownfull','t5r'),[6]=row('Ownfull','t5r')}
 for i=7,40 do entries[i]={kind='empty'} end
 local t=boot({currentPreset='Default',presets={Default={entries=entries,denyRules={},setupRules={}}},
  inviteCharacters={Ownmain=own('Ownmain','t5r'),Ownalt=own('Ownalt','t4r'),Ownfull=own('Ownfull','t5r')}},'Ownmain')
 assert(t.C.HireFromTiers(t.env.ShirsRaidBuilderDB,'Ownmain','FixtureRealm','Nobody')==nil,'unknown character got tiers')
 t:click(t:button(t.env.ShirsRaidBuilderMainFrame,'Add Normal'))
 local f=t.env.ShirsRaidBuilderAddNormal
 local first=f.characterButton.label:GetText()
 assert(first=='Ownalt' and table.concat(f.tierButton.options,',')=='t0d,t1r,t2r,t3r,t4r' and f.tierButton.label:GetText()=='t4r',
  'panel did not open on the highest tier of '..first..': '..f.tierButton.label:GetText()..' of '..table.concat(f.tierButton.options,','))
 t:choose(f.characterButton,'Ownmain')
 assert(f.characterButton.label:GetText()=='Ownmain' and f.tierButton.label:GetText()=='t5r','picking a character did not start on its highest tier: '..f.tierButton.label:GetText())
 f.tierButton.label:SetText('t2r'); t:choose(f.roleButton,'Tank')
 assert(f.tierButton.label:GetText()=='t2r','a role change replaced the chosen tier')
 f:Hide()
 -- Right-click menu: move slot 1 (T5R from Ownmain) to Ownalt, which holds T4R.
 local function card(slot)
  for _,w in ipairs(t.frames) do
   if w.kind=='Button' and w:IsVisible() and w.scripts.OnMouseUp and w.fonts[1] and string.sub(w.fonts[1]:GetText(),1,string.len(slot..' '))==slot..' ' then return w end
  end
  error('card missing: '..slot)
 end
 local function move(slot,to)
  t:fire(card(slot),'OnMouseUp','RightButton')
  local ctx=t.env.ShirsRaidBuilderContextFrame
  local live=t:preset().entries[slot]
  t:click(t:button(ctx,'Hire from: '..live.account))
  t:click(t:button(ctx,to))
  return t:preset().entries[slot]
 end
 local moved=move(1,'Ownalt')
 assert(moved.account=='Ownalt' and moved.tier=='t4r' and moved.class=='warrior' and moved.role=='mdps','T5R did not drop to Ownalt highest: '..moved.account..' '..moved.tier)
 moved=move(2,'Ownalt')
 assert(moved.account=='Ownalt' and moved.tier=='t0','the base tier changed on a move: '..moved.tier)
 moved=move(1,'Ownfull')
 assert(moved.account=='Ownalt' and moved.tier=='t4r','a move onto a character with four hires was not refused')
 moved=move(1,'Ownmain')
 assert(moved.account=='Ownmain' and moved.tier=='t4r','a move raised the tier: '..moved.tier)
 -- The card and the plan follow at once.
 assert(string.find(card(1).fonts[1]:GetText(),'Ownmain',1,true),'card did not follow the move')
 -- A character of the other faction: a class that faction cannot have is refused; any
 -- other hire takes the first race of that faction for its class.
 local db=t.env.ShirsRaidBuilderDB
 db.inviteCharacters.Ownhorde=own('Ownhorde','t3r'); db.inviteCharacters.Ownhorde.faction='Horde'
 db.characterFactions=db.characterFactions or {}; db.characterFactions.Ownhorde='Horde'
 t:preset().entries[7]={kind='normal',account='Ownalt',tier='t2r',class='paladin',role='healer',spec='default',race='human',gender='female'}
 t.env.RefreshComposition()
 local paladin=move(7,'Ownhorde')
 assert(paladin.account=='Ownalt' and paladin.race=='human','a paladin moved to a Horde character')
 local warrior=move(1,'Ownhorde')
 assert(warrior.account=='Ownhorde' and warrior.tier=='t3r' and warrior.race~='human' and warrior.race~='dwarf' and warrior.race~='gnome' and warrior.race~='nightelf',
  'a warrior moved to Horde kept an Alliance race or tier: '..tostring(warrior.race)..' '..tostring(warrior.tier))
end
-- Factions follow the hire-from character as tiers do. A linked account's rows carry each
-- character's faction, so Add Normal offers only that faction's races and classes, and so
-- does the right-click Race page. The synced faction beats one guessed from an old hire's
-- race. A character whose licences this account does not know offers only T0, and a move
-- onto it drops the tier to T0; the status line says why.
do
 local function own(name,raid,faction) return {name=name,level=60,raidLicense=raid,dungeonLicense='none',count=0,maxCount=4,faction=faction} end
 local function linked(name,raid,faction) return {name=name,level=60,dungeonLicense='none',raidLicense=raid,observed=1800000000,faction=faction} end
 local function hire(account,race) return {kind='normal',account=account,tier='t5r',class='warrior',role='mdps',spec='default',race=race,gender='male'} end
 local entries={[1]=hire('Ownmain','human'),[2]=hire('Linkhorde','orc')}
 for i=3,40 do entries[i]={kind='empty'} end
 local db={currentPreset='Default',presets={Default={entries=entries,denyRules={},setupRules={}},
   -- An old plan put a Horde race on Linkally while its faction was unknown.
   Old={entries={[1]=hire('Linkally','orc')},denyRules={},setupRules={}}},
  inviteCharacters={Ownmain=own('Ownmain','t5r','Alliance')},peerLinks={},
  peerSnapshots={['FixtureRealm;bob']={accountId='1234567890123456',source='bob',realm='FixtureRealm',received=1800000000,observed=1800000000,authoritative=false,
   entries={linked('Linkally','t4r','Alliance'),linked('Linkblank','unknown'),linked('Linkhorde','t5r','Horde')}}}}
 local link=C.PeerNew('Ownmain','Bob','FixtureRealm'); link.phase='linked'; C.LinkSave(db.peerLinks,link,true)
 local t=boot(db,'Ownmain')
 local function status()
  for _,w in ipairs(t.frames) do
   if w.kind=='FontString' and w.parent==t.env.ShirsRaidBuilderMainFrame and w.point and w.point[1]=='BOTTOMLEFT' and w.point[4]==22 and w.point[5]==16 then return w.text or '' end
  end
  error('status line missing')
 end
 t:click(t:button(t.env.ShirsRaidBuilderMainFrame,'Add Normal'))
 local f=t.env.ShirsRaidBuilderAddNormal
 local function offered(button) return table.concat(button.options,',') end
 assert(f.characterButton.label:GetText()=='Linkally','panel did not open on the first character')
 assert(offered(f.raceButton)=='Human,Gnome,Night Elf,Dwarf','an Alliance character offered '..offered(f.raceButton))
 assert(offered(f.classButton)=='Warrior,Druid,Paladin,Rogue','an Alliance character offered the classes '..offered(f.classButton))
 assert(offered(f.tierButton)=='t0d,t1r,t2r,t3r,t4r' and f.tierButton.label:GetText()=='t4r','linked tiers: '..offered(f.tierButton))
 t:choose(f.characterButton,'Linkhorde')
 assert(offered(f.raceButton)=='Orc,Undead,Tauren,Troll','a Horde character offered '..offered(f.raceButton))
 assert(f.raceButton.label:GetText()=='Orc','the race stayed on another faction: '..f.raceButton.label:GetText())
 assert(offered(f.classButton)=='Warrior,Druid,Shaman,Rogue','a Horde character offered the classes '..offered(f.classButton))
 t:choose(f.characterButton,'Linkblank')
 assert(offered(f.tierButton)=='t0d' and f.tierButton.label:GetText()=='t0d','a character with unknown licences offered '..offered(f.tierButton))
 assert(string.find(status(),'Linkblank',1,true) and string.find(status(),'only T0',1,true),'the status did not say why only T0 shows: '..status())
 f:Hide()
 local function card(slot)
  for _,w in ipairs(t.frames) do
   if w.kind=='Button' and w:IsVisible() and w.scripts.OnMouseUp and w.fonts[1] and string.sub(w.fonts[1]:GetText(),1,string.len(slot..' '))==slot..' ' then return w end
  end
  error('card missing: '..slot)
 end
 local ctx
 local function page(slot,entryLabel)
  t:fire(card(slot),'OnMouseUp','RightButton')
  ctx=t.env.ShirsRaidBuilderContextFrame
  t:click(t:button(ctx,entryLabel))
  local out={}
  for _,b in ipairs(ctx.buttons) do table.insert(out,(b.label and b.label:GetText()) or b.fonts[1]:GetText()) end
  return table.concat(out,',')
 end
 local races=page(1,'Race: Human')
 assert(races=='Back,Human,Gnome,Night Elf,Dwarf','the Race page of an Alliance hire offered '..races)
 -- Back returns to the menu; it does not close it.
 t:click(t:button(ctx,'Back'))
 assert(ctx:IsShown() and pcall(function() return t:button(ctx,'Hire from: Ownmain') end),'Back closed the menu instead of going back')
 t:click(t:button(ctx,'Close'))
 races=page(2,'Race: Orc')
 assert(races=='Back,Orc,Undead,Tauren,Troll','the Race page of a Horde hire offered '..races)
 t:click(t:button(ctx,'Back')); t:click(t:button(ctx,'Close'))
 page(1,'Hire from: Ownmain')
 t:click(t:button(ctx,'Linkblank'))
 local moved=t:preset().entries[1]
 assert(moved.account=='Linkblank' and moved.tier=='t0d','a move onto unknown licences kept '..moved.tier)
 assert(string.find(status(),'Linkblank at T0',1,true) and string.find(status(),'unknown',1,true),'the move did not say why: '..status())
 -- This account's own rows carry the faction its server list gives, so the sync sends it on.
 local rows=t.C.AccountReadLocal()
 local mine
 for _,r in ipairs(rows) do if r.name=='Ownmain' then mine=r end end
 assert(mine and mine.faction=='Alliance','own row has no faction: '..tostring(mine and mine.faction))
 rows=t.C.AccountReadLocal({{name='Ownmain',level=60,raidLicense='t5r',dungeonLicense='none',faction='Alliance'}})
 assert(rows[1].faction=='Alliance','a fresh server list lost the faction')
end
print("Shir's Raid Builder planning character tests: PASS")
