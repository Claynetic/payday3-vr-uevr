-- pd3_firstperson_fix.lua v12 -- 10 Sep 2026
-- v12: the weapon position (pull-back/height/pitch/yaw) is applied during UEVR's view calculation instead of in
--      on_pre_engine_tick. The game re-sets PawnMesh1P's transform during its own tick, so the v10/v11 writes were
--      overwritten before every frame was drawn and had no visible effect. View calculation runs after the game
--      tick and right before transforms are sent to the renderer - where UEVR's own UObjectHook attachments and
--      praydog's scripts apply theirs.
-- PAYDAY 3 draws the first-person rig (arms, weapon, tools) in Starbreeze's own "TopPass" render pass
-- (exe strings: SBZTopPassRendering, bRenderInTopPass, SetRenderInTopPass, OnTopPassFOV). That pass never
-- runs for stereo views, and UEVR makes every view a stereo view (eSSP_PRIMARY/SECONDARY, never eSSP_FULL),
-- so under UEVR the rig was never drawn. This script takes every first-person component out of TopPass
-- (SetRenderInTopPass(false), fallback: set the property + MarkRenderStateDirty) so it goes through the
-- ordinary scene pass, which UEVR renders fine. Side effects: no TopPass depth of field, and the rig is drawn
-- at its true position - see WEAPON POSITION below.
--
-- v11 (10 Sep 2026):
--   * weapon height, pitch and yaw sliders next to the pull-back (UEVR menu > LuaLoader > Script UI), all saved
--     to pd3_vr_settings.json. Pitch/yaw pivot at the eye. Height, pitch and yaw return to 0 while aiming down
--     sights (bIsTargeting) so the sights stay centred; the pull-back stays because it moves along the view axis.
--   * optional anti wall-clip (off by default): tags the 1P parts as UE5.5 "FirstPerson" primitives and enables
--     the camera's FirstPersonScale. The engine shrinks them toward each eye along its own line of sight, which
--     leaves what each eye sees unchanged but pulls their depth in front of nearby walls. Experimental: it only
--     works if PAYDAY 3's camera path honours the camera component's first-person settings (logged).
--   * defaults (tuned in-game 10 Sep 2026): pull-back 9.8 cm, height -4.2 cm, pitch/yaw 0.
-- v10 (10 Sep 2026): weapon pull-back; world scan on the first passes after every spawn (tools).
-- v9  (10 Sep 2026): pawn-scoped scan with a world-scan safety net, no address cache (every part re-checked
--     live), 1P names matched on component/actor/class names only (never the level path).
local TOPPASS_FIX        = true   -- pull the 1P rig out of TopPass (the actual fix)
local FLAG_FIX           = true   -- also clear OnlyOwnerSee/OwnerNoSee/Hidden-style flags on 1P parts, once per part
local SAFETY_EVERY       = 10     -- passes (~seconds) between world-scan safety nets
local SPAWN_WORLD_PASSES = 5      -- passes after a (re)spawn that always include the world scan
local FADE_SPEED         = 12.0   -- 1/s: how fast height/pitch/yaw blend out when aiming and back in after
local SETTINGS_FILE      = "pd3_vr_settings.json"
VIEW_HOOK = false         -- set below once the view-calculation callback is registered
local DEFAULTS = {
    pullback_cm      = 9.8,   -- toward the eyes along the view axis
    height_cm        = -4.2,  -- up (+) / down (-) in view space
    pitch_deg        = 0.0,   -- muzzle up (+) / down (-), pivot at the eye
    yaw_deg          = 0.0,   -- muzzle right (+) / left (-), pivot at the eye
    fade_when_aiming = true,  -- height/pitch/yaw -> 0 while aiming down sights
    anticlip         = false, -- experimental: UE5.5 FirstPersonScale on the 1P parts
    anticlip_scale   = 0.5,   -- depth scale toward the eye when anticlip is on (1 = none)
}

local function log(s) pcall(function() uevr.params.functions.log_info("[pd3] " .. s) end) end
local mesh_class    = uevr.api:find_uobject("Class /Script/Engine.MeshComponent")
local skel_class    = uevr.api:find_uobject("Class /Script/Engine.SkeletalMeshComponent")
local cam_class     = uevr.api:find_uobject("Class /Script/Engine.CameraComponent")
local world_classes = { skel_class, uevr.api:find_uobject("Class /Script/Engine.StaticMeshComponent") }
local hitresult_c   = uevr.api:find_uobject("ScriptStruct /Script/Engine.HitResult")
local hit_result    = hitresult_c and StructObject.new(hitresult_c) or nil
local want_loc      = Vector3d.new(0, 0, 0)
local want_rot      = Vector3d.new(0, 0, 0)   -- FRotator as (Pitch, Yaw, Roll), like praydog's scripts

local settings = {}
for k, v in pairs(DEFAULTS) do settings[k] = v end
do
    local ok, t = pcall(json.load_file, SETTINGS_FILE)
    if ok and type(t) == "table" then for k, v in pairs(DEFAULTS) do if type(t[k]) == type(v) then settings[k] = t[k] end end end
end
local function save_settings() pcall(json.dump_file, SETTINGS_FILE, settings, 4) end
log(string.format("v12 loaded  pullback=%.1f height=%.1f pitch=%.1f yaw=%.1f fade=%s anticlip=%s(%.2f) mesh_class=%s hit_result=%s",
    settings.pullback_cm, settings.height_cm, settings.pitch_deg, settings.yaw_deg, tostring(settings.fade_when_aiming),
    tostring(settings.anticlip), settings.anticlip_scale, tostring(mesh_class ~= nil), tostring(hit_result ~= nil)))

local function getp(o, n) local ok, v = pcall(function() return o:get_property(n) end); if ok then return v end; return nil end
local function setp(o, n, v) return pcall(function() o:set_property(n, v) end) end
local function callf(o, n, ...) local args = {...}; local ok, r = pcall(function() return o:call(n, table.unpack(args)) end); if ok then return r end; return nil end
local function addr(o) local ok, a = pcall(function() return o:get_address() end); if ok then return a end; return nil end
local function fname(o) local n = "nil"; if o ~= nil then pcall(function() n = o:get_full_name() end) end; return n end
local function sname(o) local n = ""; if o ~= nil then pcall(function() n = o:get_fname():to_string() end) end; return n end
local function outer(o) local ok, r = pcall(function() return o:get_outer() end); if ok then return r end; return nil end
local function toppass(o) local v = getp(o, "bRenderInTopPass"); if v == nil then return "n/a" end; return tostring(v) end
local function vec(v) if v == nil then return "nil" end; return string.format("(%.1f,%.1f,%.1f)", v.x or 0, v.y or 0, v.z or 0) end

-- 1P parts by name: the component's own name, its actor's name and its class name (never the level path).
-- "Tool" and "Throwable" cover BP_CuttingTool / BP_PhoneTool / grenades.
local function is_1p(c)
    local cls = nil; pcall(function() cls = c:get_class() end)
    local s = sname(c) .. " " .. sname(outer(c)) .. " " .. sname(cls)
    return (s:find("1P") or s:find("Equippable") or s:find("Weapon") or s:find("WPN") or s:find("Gun") or s:find("Tool") or s:find("Throwable")) ~= nil
end

-- v8 ownership test, used by the world scan: the component's actor is the pawn, or is instigated/owned by it
local function owned_by_pawn(comp, pawn)
    local actor = outer(comp); if actor == nil then return false end
    local pa = addr(pawn)
    for _ = 1, 4 do
        if addr(actor) == pa then return true end
        local inst = getp(actor, "Instigator"); if inst ~= nil and addr(inst) == pa then return true end
        local owner = getp(actor, "Owner"); if owner == nil then break end
        actor = owner
    end
    return false
end

-- The pawn carries the arms (PawnMesh1P, PawnMesh1PBody, PawnMesh1PGloves, PawnMesh1PSuit); weapons and
-- throwables are separate actors it owns. Nothing here is kept across ticks.
local function pawn_components(pawn)
    local actors, seen = {}, {}
    local function add(a, depth)
        if a == nil then return end
        local k = addr(a); if k == nil or seen[k] then return end
        seen[k] = true; actors[#actors + 1] = a
        if depth < 2 then
            local kids = getp(a, "Children")
            if type(kids) == "table" then for _, ch in ipairs(kids) do add(ch, depth + 1) end end
        end
    end
    add(pawn, 0)
    for _, p in ipairs({ "CurrentEquippable", "EquippedEquippable", "CurrentWeapon" }) do add(getp(pawn, p), 1) end
    local comps = {}
    if mesh_class ~= nil then
        for _, a in ipairs(actors) do
            local ok, list = pcall(function() return a:K2_GetComponentsByClass(mesh_class) end)
            if ok and type(list) == "table" then for _, c in ipairs(list) do comps[#comps + 1] = c end end
        end
    end
    return comps, #actors
end

local function world_components(pawn)
    local comps = {}
    for _, cls in ipairs(world_classes) do if cls ~= nil then
        for _, c in ipairs(UEVR_UObjectHook.get_objects_by_class(cls, false)) do
            if owned_by_pawn(c, pawn) then comps[#comps + 1] = c end
        end
    end end
    return comps
end

-- take one component out of TopPass. Returns "fn" / "prop" / "fail".
local function untoppass(c)
    if pcall(function() c:call("SetRenderInTopPass", false) end) then
        if getp(c, "bRenderInTopPass") == false then return "fn" end
    end
    if setp(c, "bRenderInTopPass", false) then
        pcall(function() c:call("MarkRenderStateDirty") end)
        if getp(c, "bRenderInTopPass") == false then return "prop" end
    end
    return "fail"
end

local function clear_flags(c, name)
    local did = {}
    if getp(c, "bOnlyOwnerSee") == true then if pcall(function() c:call("SetOnlyOwnerSee", false) end) then did[#did+1] = "OnlyOwnerSee=0" end end
    if getp(c, "bOwnerNoSee") == true then if pcall(function() c:call("SetOwnerNoSee", false) end) then did[#did+1] = "OwnerNoSee=0" end end
    if getp(c, "bRenderInMainPass") == false then if pcall(function() c:call("SetRenderInMainPass", true) end) then did[#did+1] = "MainPass=1" end end
    if getp(c, "bUseViewOwnerDepthPriorityGroup") == true then if setp(c, "bUseViewOwnerDepthPriorityGroup", false) then did[#did+1] = "ViewOwnerDPG=0" end end
    if getp(c, "bVisibleInSceneCaptureOnly") == true then if setp(c, "bVisibleInSceneCaptureOnly", false) then did[#did+1] = "SceneCaptureOnly=0" end end
    if getp(c, "bHiddenInGame") == true then if pcall(function() c:call("SetHiddenInGame", false, false) end) then did[#did+1] = "Hidden=0" end end
    if #did > 0 then pcall(function() c:call("MarkRenderStateDirty") end); log("forced " .. table.concat(did, ",") .. " on " .. name) end
end

-- ---- ANTI WALL-CLIP (experimental, UE5.5 first-person rendering) ----------------------------------------
-- 1P parts get FirstPersonPrimitiveType=FirstPerson (1) and the pawn's camera gets bEnableFirstPersonScale.
-- Only ever reverted if this script changed it (the game itself leaves both off).
local ac = { touched = false, cams = 0, last_state = nil }
local function sync_fp_type(c)
    local want = settings.anticlip and 1 or 0
    if not settings.anticlip and not ac.touched then return end
    local t = tonumber(getp(c, "FirstPersonPrimitiveType"))
    if t == nil or t == want then return end
    if not pcall(function() c:call("SetFirstPersonPrimitiveType", want) end) then
        setp(c, "FirstPersonPrimitiveType", want); pcall(function() c:call("MarkRenderStateDirty") end)
    end
end
local function pov_first_person()
    local pc = uevr.api:get_player_controller(0); if pc == nil then return "no controller" end
    local pov = getp(getp(getp(pc, "PlayerCameraManager"), "CameraCachePrivate") or {}, "POV")
    if pov == nil then return "POV unreadable" end
    return string.format("POV bUseFirstPersonParameters=%s FirstPersonScale=%s", tostring(getp(pov, "bUseFirstPersonParameters")), tostring(getp(pov, "FirstPersonScale")))
end
local function sync_camera(pawn)
    if cam_class == nil or (not settings.anticlip and not ac.touched) then return end
    local ok, cams = pcall(function() return pawn:K2_GetComponentsByClass(cam_class) end)
    if not ok or type(cams) ~= "table" then cams = {} end
    ac.cams = #cams
    for _, cam in ipairs(cams) do
        if settings.anticlip then
            if getp(cam, "bEnableFirstPersonScale") ~= true then setp(cam, "bEnableFirstPersonScale", true) end
            local s = getp(cam, "FirstPersonScale")
            if type(s) == "number" and math.abs(s - settings.anticlip_scale) > 0.001 then setp(cam, "FirstPersonScale", settings.anticlip_scale) end
        elseif getp(cam, "bEnableFirstPersonScale") == true then
            setp(cam, "bEnableFirstPersonScale", false)
        end
    end
    if settings.anticlip then ac.touched = true end
    local state = tostring(settings.anticlip) .. string.format("%.2f", settings.anticlip_scale)
    if state ~= ac.last_state then
        ac.last_state = state
        log(string.format("anti wall-clip %s (scale %.2f): %d camera component(s) on the pawn; %s",
            settings.anticlip and "ON" or "off", settings.anticlip_scale, ac.cams, pov_first_person()))
    end
end

-- Keyed by full object name (unique per instance), never by address.
--   flags_done: FLAG_FIX runs once per part, so the game can still hide a tool on purpose afterwards.
--   tp_failed:  a part that refused to leave TopPass is not retried (and logged) every second.
local flags_done, tp_failed = {}, {}

local function handle(c, name, dump, st)
    local one_p = is_1p(c)
    local tp = getp(c, "bRenderInTopPass")
    if one_p then st.seen = st.seen + 1; if tp == nil then st.na = st.na + 1 end end
    if tp == true then
        st.tp = st.tp + 1
        if TOPPASS_FIX and not tp_failed[name] then
            local how = untoppass(c)
            if how == "fail" then tp_failed[name] = true else st.moved = st.moved + 1 end
            log("TopPass -> main pass via " .. how .. " on " .. name)
        end
    end
    if FLAG_FIX and one_p and not flags_done[name] then
        flags_done[name] = true
        clear_flags(c, name)
    end
    if one_p then sync_fp_type(c) end
    if dump then
        log(string.format("  %s | 1p=%s topPass=%s fp=%s rendered=%s vis=%s hid=%s onlyOwner=%s ownerNoSee=%s",
            name, tostring(one_p), toppass(c), tostring(getp(c, "FirstPersonPrimitiveType")), tostring(callf(c, "WasRecentlyRendered", 0.2)),
            tostring(getp(c, "bVisible")), tostring(getp(c, "bHiddenInGame")), tostring(getp(c, "bOnlyOwnerSee")), tostring(getp(c, "bOwnerNoSee"))))
    end
end

-- ---- WEAPON POSITION (pull-back, height, pitch, yaw) ----------------------------------------------------
-- PawnMesh1P hangs off the pawn's FirstPersonCameraAttachment (X = view direction, Z = up, origin at the eye),
-- and the weapon/tools hang off PawnMesh1P, so one relative transform moves the whole rig. The game re-sets that
-- transform every frame (v10 log: re-read 60x/s), so each frame: if the current transform is not the one we
-- last wrote, it becomes the new base; then write  rot = base * offset,  loc = base_loc * offset + translation.
local rad, deg = math.rad, math.deg
local function rot_matrix(p, y, r)   -- UE FRotationMatrix; rows are the X (forward), Y (right), Z (up) axes
    local sp, cp = math.sin(rad(p)), math.cos(rad(p))
    local sy, cy = math.sin(rad(y)), math.cos(rad(y))
    local sr, cr = math.sin(rad(r)), math.cos(rad(r))
    return { { cp * cy, cp * sy, sp },
             { sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp },
             { -(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp } }
end
local function mat_mul(a, b)          -- row vectors: v * (a * b) = (v * a) * b, i.e. a first, then b
    local m = {}
    for i = 1, 3 do m[i] = {}; for j = 1, 3 do m[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end end
    return m
end
local function vec_mul(v, m)
    return { x = v.x * m[1][1] + v.y * m[2][1] + v.z * m[3][1],
             y = v.x * m[1][2] + v.y * m[2][2] + v.z * m[3][2],
             z = v.x * m[1][3] + v.y * m[2][3] + v.z * m[3][3] }
end
local function matrix_to_rotator(m)  -- FMatrix::Rotator
    local x, y, z = m[1], m[2], m[3]
    local pitch = deg(math.atan(x[3], math.sqrt(x[1] * x[1] + x[2] * x[2])))
    local yaw   = deg(math.atan(x[2], x[1]))
    local sya   = rot_matrix(pitch, yaw, 0)[2]
    local roll  = deg(math.atan(z[1] * sya[1] + z[2] * sya[2] + z[3] * sya[3], y[1] * sya[1] + y[2] * sya[2] + y[3] * sya[3]))
    return pitch, yaw, roll
end
local function ang_diff(a, b) local d = (a - b) % 360; if d > 180 then d = d - 360 end; return math.abs(d) end
local function xyz(v)                 -- FVector / FRotator read back as Vector3d (x,y,z = Pitch,Yaw,Roll) or StructObject
    if v == nil then return nil end
    local ok, x = pcall(function() return v.x end)
    if ok and type(x) == "number" then return { x = v.x, y = v.y, z = v.z } end
    local p = getp(v, "Pitch"); if type(p) == "number" then return { x = p, y = getp(v, "Yaw"), z = getp(v, "Roll") } end
    local vx = getp(v, "X"); if type(vx) == "number" then return { x = vx, y = getp(v, "Y"), z = getp(v, "Z") } end
    return nil
end
local function same_loc(a, b) return math.abs(a.x - b.x) < 0.01 and math.abs(a.y - b.y) < 0.01 and math.abs(a.z - b.z) < 0.01 end
local function same_rot(a, b) return ang_diff(a.x, b.x) < 0.05 and ang_diff(a.y, b.y) < 0.05 and ang_diff(a.z, b.z) < 0.05 end

local rig = { base_loc = nil, base_rot = nil, w_loc = nil, w_rot = nil, key = nil, alpha = 1.0, rebases = 0, announced = false }
local aim = { src = nil, targeting = false }

local function rig_root(pawn)
    local m = getp(pawn, "PawnMesh1P")
    if m ~= nil then return m end
    if skel_class == nil then return nil end
    local ok, list = pcall(function() return pawn:K2_GetComponentsByClass(skel_class) end)
    if ok and type(list) == "table" then for _, c in ipairs(list) do if sname(c) == "PawnMesh1P" then return c end end end
    return nil
end

local function is_targeting(pawn)
    local v, src = getp(pawn, "bIsTargeting"), "pawn"
    if v == nil then
        local eq = getp(pawn, "CurrentEquippable")
        if eq ~= nil then v, src = getp(eq, "bIsTargeting"), "equippable" end
    end
    if v ~= nil and aim.src == nil then aim.src = src; log("aim detection: bIsTargeting found on the " .. src) end
    return v == true
end

local function apply_rig(pawn, delta)
    if hit_result == nil then return end
    local mesh = rig_root(pawn); if mesh == nil then return end
    local cl, cr = xyz(getp(mesh, "RelativeLocation")), xyz(getp(mesh, "RelativeRotation"))
    if cl == nil or cr == nil then return end

    aim.targeting = settings.fade_when_aiming and is_targeting(pawn) or false
    local target = aim.targeting and 0.0 or 1.0
    rig.alpha = rig.alpha + (target - rig.alpha) * math.min(1.0, (delta or 0.016) * FADE_SPEED)
    if math.abs(rig.alpha - target) < 0.002 then rig.alpha = target end

    local ours = rig.w_loc ~= nil and same_loc(cl, rig.w_loc) and same_rot(cr, rig.w_rot)
    if not ours then rig.base_loc, rig.base_rot = cl, cr; rig.rebases = rig.rebases + 1 end

    local a = rig.alpha
    local h, po, yo = settings.height_cm * a, settings.pitch_deg * a, settings.yaw_deg * a
    local key = string.format("%.3f|%.3f|%.3f|%.3f", settings.pullback_cm, h, po, yo)
    if ours and key == rig.key then return end                                -- our transform is still in place

    local off = rot_matrix(po, yo, 0)
    local np, ny, nr = matrix_to_rotator(mat_mul(rot_matrix(rig.base_rot.x, rig.base_rot.y, rig.base_rot.z), off))
    local nl = vec_mul(rig.base_loc, off)
    want_loc.x, want_loc.y, want_loc.z = nl.x - settings.pullback_cm, nl.y, nl.z + h
    want_rot.x, want_rot.y, want_rot.z = np, ny, nr
    local ok = pcall(function() mesh:K2_SetRelativeLocationAndRotation(want_loc, want_rot, false, hit_result, false) end)
    if not ok then
        ok = pcall(function() mesh:K2_SetRelativeLocation(want_loc, false, hit_result, false) end)
        pcall(function() mesh:K2_SetRelativeRotation(want_rot, false, hit_result, false) end)
    end
    if not ok then return end
    rig.w_loc = { x = want_loc.x, y = want_loc.y, z = want_loc.z }
    rig.w_rot = { x = np, y = ny, z = nr }
    rig.key = key
    if not rig.announced then
        rig.announced = true
        log(string.format("weapon position on %s (parent %s): base loc %s rot %s -> loc %s rot (%.1f,%.1f,%.1f)",
            sname(mesh), sname(getp(mesh, "AttachParent")), vec(rig.base_loc), vec(rig.base_rot), vec(rig.w_loc), np, ny, nr))
    end
end

-- ---- UEVR menu (LuaLoader > Script UI) ------------------------------------------------------------------
pcall(function()
    uevr.sdk.callbacks.on_draw_ui(function()
        local dirty, ch, v = false, false, nil
        imgui.text("PAYDAY 3 VR - first-person fix v12  (position applied: " .. (VIEW_HOOK and "view calculation" or "engine tick - fallback") .. ")")
        ch, v = imgui.slider_float("Pull-back (cm)", settings.pullback_cm, 0.0, 30.0); if ch then settings.pullback_cm = v; dirty = true end
        ch, v = imgui.slider_float("Height (cm)", settings.height_cm, -10.0, 10.0); if ch then settings.height_cm = v; dirty = true end
        ch, v = imgui.slider_float("Pitch (deg)", settings.pitch_deg, -20.0, 20.0); if ch then settings.pitch_deg = v; dirty = true end
        ch, v = imgui.slider_float("Yaw (deg)", settings.yaw_deg, -20.0, 20.0); if ch then settings.yaw_deg = v; dirty = true end
        ch, v = imgui.checkbox("Return height/pitch/yaw to 0 while aiming", settings.fade_when_aiming); if ch then settings.fade_when_aiming = v; dirty = true end
        imgui.text(aim.src and ("  aim detection: bIsTargeting on the " .. aim.src .. (aim.targeting and "  [aiming]" or "")) or "  aim detection: not found yet")
        imgui.separator()
        ch, v = imgui.checkbox("Anti wall-clip (experimental)", settings.anticlip); if ch then settings.anticlip = v; dirty = true end
        if settings.anticlip then
            ch, v = imgui.slider_float("Anti wall-clip depth scale", settings.anticlip_scale, 0.05, 1.0); if ch then settings.anticlip_scale = v; dirty = true end
            imgui.text("  " .. tostring(ac.cams) .. " camera component(s); see [pd3] anti wall-clip line in log.txt")
        end
        imgui.separator()
        if imgui.button("Reset to defaults") then for k, d in pairs(DEFAULTS) do settings[k] = d end; dirty = true end
        imgui.text("Saved to " .. SETTINGS_FILE .. ". Pair with UEVR Near Clip Plane ~1 cm.")
        if dirty then save_settings() end
    end)
end)

-- ---- main loop ------------------------------------------------------------------------------------------
local tick, pass, lastdump, ndump = 0, 0, 0, 0
local summary_done, world_only_logged = false, false
local last_pawn, spawn_passes = nil, 0
local last_delta, fade_tick = 0.016, -1

-- The game re-sets PawnMesh1P's transform during its own tick (after on_pre_engine_tick), so the weapon position is
-- applied during view calculation: after the game tick, just before the frame's transforms go to the renderer.
-- Called once per eye; the second call is a no-op (transform already ours) and the aim fade advances once per frame.
VIEW_HOOK = pcall(function()
    uevr.sdk.callbacks.on_early_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
        local pawn = uevr.api:get_local_pawn(0); if pawn == nil then return end
        local d = 0.0
        if fade_tick ~= tick then fade_tick = tick; d = last_delta end
        pcall(apply_rig, pawn, d)
    end)
end)
log("weapon position applied " .. (VIEW_HOOK and "during view calculation" or "in on_pre_engine_tick (view callback unavailable - may be overwritten by the game)"))

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    tick = tick + 1
    last_delta = delta or last_delta
    local pawn = uevr.api:get_local_pawn(0); if pawn == nil then return end
    if not VIEW_HOOK then pcall(apply_rig, pawn, delta) end                   -- fallback only
    if tick % 60 ~= 0 then return end

    pass = pass + 1
    local pa = addr(pawn)                                                     -- compared only, never dereferenced
    if pa ~= last_pawn then last_pawn = pa; spawn_passes = SPAWN_WORLD_PASSES end
    local dump = (tick - lastdump) >= 600 and ndump < 8
    if dump then
        lastdump = tick; ndump = ndump + 1
        log("=== dump " .. ndump .. " pawn=" .. fname(pawn) .. " equippable=" .. fname(getp(pawn, "CurrentEquippable")))
        log(string.format("  weapon: pull-back %.1f height %.1f pitch %.1f yaw %.1f (alpha %.2f), base re-read %d times; aim=%s; anticlip=%s; %s",
            settings.pullback_cm, settings.height_cm, settings.pitch_deg, settings.yaw_deg, rig.alpha, rig.rebases,
            tostring(aim.src or "not found"), tostring(settings.anticlip), pov_first_person()))
    end
    pcall(sync_camera, pawn)

    local st = { seen = 0, tp = 0, na = 0, moved = 0 }
    local comps, n_actors = pawn_components(pawn)
    local done = {}
    for _, c in ipairs(comps) do
        local name = fname(c)
        done[name] = true
        handle(c, name, dump, st)
    end

    local after_spawn = spawn_passes > 0
    if after_spawn then spawn_passes = spawn_passes - 1 end
    local world = (#comps == 0) or after_spawn or (pass % SAFETY_EVERY == 0)
    if #comps == 0 and not world_only_logged then
        world_only_logged = true
        log("pawn scan found no mesh components (" .. n_actors .. " actors) - using the world scan every pass")
    end
    if world then
        for _, c in ipairs(world_components(pawn)) do
            local name = fname(c)
            if not done[name] then
                if #comps > 0 and not after_spawn and not tp_failed[name] and getp(c, "bRenderInTopPass") == true then
                    log("world scan caught a TopPass part the pawn scan missed: " .. name)
                end
                handle(c, name, dump, st)
            end
        end
    end

    -- one-line verdict the first time we have seen the rig, then again on every dump
    if st.seen > 0 and (dump or not summary_done) then
        summary_done = true
        log(string.format("TopPass summary: 1P components=%d  bRenderInTopPass=true:%d  property n/a:%d  moved to main pass this tick:%d  (scan: pawn %d actors/%d comps%s, TOPPASS_FIX=%s)",
            st.seen, st.tp, st.na, st.moved, n_actors, #comps, world and " + world" or "", tostring(TOPPASS_FIX)))
        if st.na == st.seen then log("bRenderInTopPass is NOT reachable through reflection on any 1P component -> the fix cannot act on this build") end
    end
end)
