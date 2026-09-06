-- pd3_firstperson_fix.lua v8 -- 5 Sep 2026
-- Facts established by the 4 Sep runs (both 20:49 and 21:15):
--   * every 1P mesh reports FirstPersonPrimitiveType=0  -> H1 (UE5.5 first-person primitive) is dead; FP_FIX is a no-op
--   * Native Stereo Fix engaged (scene capture created) and arms were STILL absent
--   * arms/legs/weapon are absent in the flat desktop window and in UEVR 2D Screen Mode too
--   => the rig is not drawn at all while UEVR is attached. Starbreeze draws the 1P rig in its own
--      "TopPass" (exe strings: SBZTopPassRendering, bRenderInTopPass, SetRenderInTopPass, OnTopPassFOV,
--      FSBZRestoreTopPassPS ...). Working hypothesis: TopPass early-outs for stereo views, and UEVR makes
--      every view a stereo view (eSSP_PRIMARY/SECONDARY, never eSSP_FULL).
-- v8 therefore stops repairing TopPass and takes the rig OUT of it: for every pawn-owned 1P mesh / weapon
-- part / tool with bRenderInTopPass=true, call SetRenderInTopPass(false) (fallback: set the property and
-- MarkRenderStateDirty). The rig should then go through the ordinary main pass, which UEVR renders fine.
-- Expected side effects: rig drawn at world FOV (bigger/closer), possible near-plane clipping (-> UEVR
-- Near Clip Plane option), no TopPass depth of field. Everything is logged so a failed run still tells us
-- (a) whether the property is reachable through reflection and (b) on which class it lives.
--
-- Run A (this file as shipped):  TOPPASS_FIX=true, no plugin.
-- Run B (gate hypothesis test):  TOPPASS_FIX=false + pd3_fullpass.dll in the profile's plugins folder,
--                                VR_RenderingMethod=1 (Synchronized Sequential).
local TOPPASS_FIX = true    -- (v8) pull the 1P rig out of Starbreeze's TopPass
local FLAG_FIX    = true    -- (v6) drop OnlyOwnerSee/OwnerNoSee/Hidden etc. (kept: harmless, proven to apply)
local TOPFOV_FIX  = false   -- (v6) OnTopBaseFOV 55 -> 90. Off: irrelevant once the rig leaves TopPass
local FP_FIX      = false   -- (v7) UE5.5 first-person neutralisation. Off: proven no-op (FPtype=0 everywhere)

local function log(s) pcall(function() uevr.params.functions.log_info("[pd3] " .. s) end) end
local classes = { uevr.api:find_uobject("Class /Script/Engine.SkeletalMeshComponent"), uevr.api:find_uobject("Class /Script/Engine.StaticMeshComponent") }
local camclass = uevr.api:find_uobject("Class /Script/Engine.CameraComponent")
log("v8 loaded  TOPPASS_FIX=" .. tostring(TOPPASS_FIX) .. " FLAG_FIX=" .. tostring(FLAG_FIX) .. " TOPFOV_FIX=" .. tostring(TOPFOV_FIX) .. " FP_FIX=" .. tostring(FP_FIX))
local function getp(o, n) local ok, v = pcall(function() return o:get_property(n) end); if ok then return v end; return nil end
local function setp(o, n, v) return pcall(function() o:set_property(n, v) end) end
local function callf(o, n, ...) local args = {...}; local ok, r = pcall(function() return o:call(n, table.unpack(args)) end); if ok then return r end; return nil end
local function addr(o) local ok, a = pcall(function() return o:get_address() end); if ok then return a end; return nil end
local function fname(o) local n = "nil"; if o ~= nil then pcall(function() n = o:get_full_name() end) end; return n end
local function owned_by_pawn(comp, pawn)
    local ok, actor = pcall(function() return comp:get_outer() end); if not ok or actor == nil then return false end
    local pa = addr(pawn)
    for _ = 1, 4 do
        if addr(actor) == pa then return true end
        local inst = getp(actor, "Instigator"); if inst ~= nil and addr(inst) == pa then return true end
        local owner = getp(actor, "Owner"); if owner == nil then break end
        actor = owner
    end
    return false
end
local function vec(v) if v == nil then return "nil" end; return string.format("(%.1f,%.1f,%.1f)", v.x or 0, v.y or 0, v.z or 0) end
-- (v8) "Tool" and "Throwable" added: BP_CuttingTool / BP_PhoneTool / grenades are 1P items too
local function is_1p(name) return (name:find("1P") or name:find("Equippable") or name:find("Weapon") or name:find("WPN") or name:find("Gun") or name:find("Tool") or name:find("Throwable")) ~= nil end

local function fp_type(c)
    local v = getp(c, "FirstPersonPrimitiveType")
    if v == nil then return "n/a", nil end
    if type(v) == "number" then return tostring(v), v end
    local s = tostring(v); local n = nil
    if s:find("FirstPerson") and not s:find("None") then n = 1 elseif s:find("None") then n = 0 end
    return s, n
end

-- (v8) TopPass state of one object: property value ("n/a" when reflection does not expose it)
local function toppass(o) local v = getp(o, "bRenderInTopPass"); if v == nil then return "n/a" end; return tostring(v) end

-- (v8) take one component out of TopPass. Returns "fn" / "prop" / "fail".
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

local tick, lastdump, ndump, fixed_addrs, fp_fixed, cam_fixed, tp_fixed = 0, 0, 0, {}, {}, {}, {}
local tp_summary_done = false
uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    tick = tick + 1
    if tick % 60 ~= 0 then return end
    local pawn = uevr.api:get_local_pawn(0); if pawn == nil then return end
    local dump = (tick - lastdump) >= 600 and ndump < 8
    local equip = getp(pawn, "CurrentEquippable") or getp(pawn, "EquippedEquippable") or getp(pawn, "CurrentWeapon")
    if dump then
        lastdump = tick; ndump = ndump + 1
        log("=== dump " .. ndump .. " pawn=" .. fname(pawn) .. " OnTopBaseFOV=" .. tostring(getp(pawn, "OnTopBaseFOV")) .. " equippable=" .. fname(equip))
        -- (v8) actor-level TopPass fields, in case the switch lives on the pawn / equippable rather than the component
        log(string.format("  pawn bRenderInTopPass=%s OnTopPassFOV=%s TopPassFieldOfViewAngle=%s | equippable bRenderInTopPass=%s",
            toppass(pawn), tostring(getp(pawn, "OnTopPassFOV")), tostring(getp(pawn, "TopPassFieldOfViewAngle")), equip and toppass(equip) or "nil"))
    end

    if TOPFOV_FIX then
        local fov = getp(pawn, "OnTopBaseFOV")
        if fov ~= nil and fov < 80 then if setp(pawn, "OnTopBaseFOV", 90.0) then log("OnTopBaseFOV " .. tostring(fov) .. " -> 90") end end
    end

    if camclass ~= nil and (FP_FIX or dump) then
        for _, cam in ipairs(UEVR_UObjectHook.get_objects_by_class(camclass, false)) do
            if owned_by_pawn(cam, pawn) then
                local a = addr(cam)
                local fpfov, fpscale = getp(cam, "bEnableFirstPersonFieldOfView"), getp(cam, "bEnableFirstPersonScale")
                if dump then
                    log(string.format("  CAM %s | bEnableFirstPersonFieldOfView=%s bEnableFirstPersonScale=%s FieldOfView=%s",
                        fname(cam), tostring(fpfov), tostring(fpscale), tostring(getp(cam, "FieldOfView"))))
                end
                if FP_FIX and a and not cam_fixed[a] and (fpfov == true or fpscale == true) then
                    cam_fixed[a] = true
                    setp(cam, "bEnableFirstPersonFieldOfView", false); setp(cam, "bEnableFirstPersonScale", false)
                    log("  CAM first-person flags cleared on " .. fname(cam))
                end
            end
        end
    end

    local n_seen, n_tp_true, n_tp_na, n_moved = 0, 0, 0, 0
    for _, cls in ipairs(classes) do if cls ~= nil then
        for _, c in ipairs(UEVR_UObjectHook.get_objects_by_class(cls, false)) do
            local name = fname(c)
            local mine = owned_by_pawn(c, pawn)
            if mine and is_1p(name) then
                local a = addr(c)
                n_seen = n_seen + 1
                local tp = getp(c, "bRenderInTopPass")
                if tp == nil then n_tp_na = n_tp_na + 1 elseif tp == true then n_tp_true = n_tp_true + 1 end

                -- (v8) the actual fix
                if TOPPASS_FIX and a and not tp_fixed[a] and tp == true then
                    tp_fixed[a] = true
                    local how = untoppass(c)
                    if how ~= "fail" then n_moved = n_moved + 1 end
                    log("TopPass -> main pass via " .. how .. " on " .. name)
                end

                if FP_FIX and a and not fp_fixed[a] then
                    local fps, fpn = fp_type(c)
                    if fpn ~= nil and fpn ~= 0 then
                        fp_fixed[a] = true
                        local ok = pcall(function() c:call("SetFirstPersonPrimitiveType", 0) end)
                        if not ok then ok = setp(c, "FirstPersonPrimitiveType", 0); pcall(function() c:call("MarkRenderStateDirty") end) end
                        log("FP primitive " .. fps .. " -> None (" .. tostring(ok) .. ") on " .. name)
                    end
                end

                if FLAG_FIX and a and not fixed_addrs[a] then
                    fixed_addrs[a] = true
                    local did = {}
                    if getp(c, "bOnlyOwnerSee") == true then if pcall(function() c:call("SetOnlyOwnerSee", false) end) then did[#did+1] = "OnlyOwnerSee=0" end end
                    if getp(c, "bOwnerNoSee") == true then if pcall(function() c:call("SetOwnerNoSee", false) end) then did[#did+1] = "OwnerNoSee=0" end end
                    if getp(c, "bRenderInMainPass") == false then if pcall(function() c:call("SetRenderInMainPass", true) end) then did[#did+1] = "MainPass=1" end end
                    if getp(c, "bUseViewOwnerDepthPriorityGroup") == true then if setp(c, "bUseViewOwnerDepthPriorityGroup", false) then did[#did+1] = "ViewOwnerDPG=0" end end
                    if getp(c, "bVisibleInSceneCaptureOnly") == true then if setp(c, "bVisibleInSceneCaptureOnly", false) then did[#did+1] = "SceneCaptureOnly=0" end end
                    if getp(c, "bHiddenInGame") == true then if pcall(function() c:call("SetHiddenInGame", false, false) end) then did[#did+1] = "Hidden=0" end end
                    if #did > 0 then pcall(function() c:call("MarkRenderStateDirty") end); log("forced " .. table.concat(did, ",") .. " on " .. name) end
                end
            end
            if dump and mine then
                local loc = callf(c, "K2_GetComponentLocation")
                local wrr = callf(c, "WasRecentlyRendered", 0.2)
                log(string.format("  %s | topPass=%s | rendered=%s | vis=%s hid=%s onlyOwner=%s ownerNoSee=%s mainPass=%s custDepth=%s | mesh=%s | loc=%s | parent=%s",
                    name, toppass(c), tostring(wrr),
                    tostring(getp(c,"bVisible")), tostring(getp(c,"bHiddenInGame")), tostring(getp(c,"bOnlyOwnerSee")), tostring(getp(c,"bOwnerNoSee")),
                    tostring(getp(c,"bRenderInMainPass")), tostring(getp(c,"bRenderCustomDepth")),
                    fname(getp(c,"SkeletalMeshAsset") or getp(c,"SkeletalMesh") or getp(c,"StaticMesh")),
                    vec(loc), fname(getp(c,"AttachParent"))))
            end
        end
    end end

    -- (v8) one-line verdict the first time we have seen the rig, then again on every dump
    if n_seen > 0 and (dump or not tp_summary_done) then
        tp_summary_done = true
        log(string.format("TopPass summary: 1P components=%d  bRenderInTopPass=true:%d  property n/a:%d  moved to main pass this tick:%d  (TOPPASS_FIX=%s)",
            n_seen, n_tp_true, n_tp_na, n_moved, tostring(TOPPASS_FIX)))
        if n_tp_na == n_seen then log("bRenderInTopPass is NOT reachable through reflection on any 1P component -> v8 cannot act; go to Run B (plugin)") end
    end

    if dump then
        local pc = uevr.api:get_player_controller(0)
        if pc ~= nil then
            local cam = getp(pc, "PlayerCameraManager"); local cl, fovv = nil, nil
            if cam ~= nil then cl = callf(cam, "GetCameraLocation"); fovv = callf(cam, "GetFOVAngle") end
            log("camera loc=" .. vec(cl) .. " fov=" .. tostring(fovv) .. " viewTarget=" .. fname(callf(pc, "GetViewTarget")))
        end
    end
end)
