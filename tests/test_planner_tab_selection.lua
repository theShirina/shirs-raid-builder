-- Registered handlers, not a selected-state boolean alone.
local f=assert(io.open('test_individual_editor.lua'));local src=f:read('*a');f:close()
local at=assert(string.find(src,'\nlocal failures, passes=',1,true));local boot=assert(loadstring(string.sub(src,1,at-1)..'\nreturn boot'))()
local h=boot();h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn);local p=h.C.plannerFrame
local function color(v)return table.concat(v or {},',') end
local pass=0
for _,tab in ipairs({{'Sources','sources'},{'Composition','counts'},{'Proposed groups','proposal'},{'Tier priority','priority'}}) do
 local active=h:button(p,tab[1]);h:click(active);local selected=color(active.backdropColor);local border=color(active.borderColor);local text=color(active.label.textColor)
 local other=h:button(p,tab[1]=='Sources' and 'Composition' or 'Sources');local idle=color(other.backdropColor)
 assert(selected~=idle,'active tab has no persistent distinct fill: '..tab[1])
 h:fire(active,'OnEnter');h:fire(active,'OnLeave')
 assert(color(active.backdropColor)==selected and color(active.borderColor)==border and color(active.label.textColor)==text,'leaving active tab cleared selection')
 h:fire(other,'OnEnter');assert(color(other.backdropColor)~=idle and color(other.backdropColor)~=selected,'hover is not distinct from selected')
 assert(color(active.backdropColor)==selected and p.tab==tab[2] and p.panels[tab[2]]:IsShown(),'hover moved or hid selected page')
 h:fire(other,'OnLeave');assert(color(other.backdropColor)==idle and color(active.backdropColor)==selected)
 pass=pass+1;print('PASS persistent selection separate from hover: '..tab[1])
end
h.C.ClosePlanner();h:click(h.env.ShirsRaidBuilderMainFrame.plannerBtn)
assert(p.tab=='sources' and color(h:button(p,'Sources').backdropColor)~=color(h:button(p,'Composition').backdropColor),'reopen left stale selected styling')
print("Shir's Raid Builder tab selection tests: PASS ("..pass..' tabs plus reopen)')
