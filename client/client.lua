local display = false
local isTransitioningTime = false

-- Resource Name Protection
local REQ_NAME = "bk_admin"
if GetCurrentResourceName() ~= REQ_NAME then
    Citizen.CreateThread(function()
        while true do
            print("^1[FATAL ERROR] bk_admin: UNAUTHORIZED RESOURCE NAME CHANGE DETECTED!^7")
            Citizen.Wait(5000)
        end
    end)
    return
end

local isNoClip = false
local isInvisible = false
local isGodmode = false
local isSpectating = false
local isOnDuty = false
local isSuperAdmin = false
-- keep single source of truth for vanish state (declared at top)
local showPlayerIDs = false
local currentRank = ""
local isGod = false
local spectateTarget = nil
local noclipSpeed = 0.5
local currentDensity = 1.0
local selectedPlayerName = ""
local originalModel = nil
local selectedBanReason = ""
local selectedBanDuration = ""
local hasSyncedTime = false
local lastTimeSync = 0
local inputActive = false
local frozenPlayers = {}  -- Track frozen state of other players
local spawnedObjects = {}  -- Track spawned objects for deletion

local function updateNuiFocus()
    -- Show cursor only while input dialog is active. Keep keyboard input when menu is open.
    local wantFocus = display or inputActive
    SetNuiFocus(wantFocus, inputActive)
    SetNuiFocusKeepInput(wantFocus and not inputActive)  -- Only keep input when menu is open, NOT when input dialog is active
end
local pendingInputCallback = nil
local pendingInputData = nil

function L(key)
    if Locales[Config.Locale] and Locales[Config.Locale][key] then
        return Locales[Config.Locale][key]
    end
    return key
end

-- Custom Input Dialog Helper
function OpenInput(title, callback, callbackData, defaultText, maxLength, placeholder)
    pendingInputCallback = callback
    pendingInputData = callbackData
    inputActive = true
    updateNuiFocus()
    SendNUIMessage({
        action = 'openInput',
        data = {
            title = title or 'Eingabe',
            callback = 'handleInput',
            defaultText = defaultText or '',
            maxLength = maxLength or 200,
            placeholder = placeholder or ''
        }
    })
end

-- Direction vector helper
function getCamDirection()
    local heading = GetGameplayCamRelativeHeading() + GetEntityHeading(PlayerPedId())
    local pitch = GetGameplayCamRelativePitch()
    local x = -math.sin(math.rad(heading)) * math.abs(math.cos(math.rad(pitch)))
    local y = math.cos(math.rad(heading)) * math.abs(math.cos(math.rad(pitch)))
    local z = math.sin(math.rad(pitch))
    return x, y, z
end

-- Main thread for Controls (Movement while menu is open)
Citizen.CreateThread(function()
    while true do
        if display then
            if inputActive then
                -- HARD LOCK ALL CONTROLS while input dialog is active
                DisableAllControlActions(0)
                DisableAllControlActions(1)
                DisableAllControlActions(2)
                -- Triple-lock the most problematic keys
                for i = 0, 221 do
                    DisableControlAction(0, i, true)
                    DisableControlAction(1, i, true)
                    DisableControlAction(2, i, true)
                end
            else
                -- Only disable specific controls while menu is open (not input)
                DisableControlAction(0, 142, true) -- Melee
                DisableControlAction(0, 106, true) -- Vehicle Mouse Control
                DisableControlAction(0, 24, true) -- Attack
                DisableControlAction(0, 25, true) -- Aim
            end
            Citizen.Wait(0)
        else
            Citizen.Wait(500)
        end
    end
end)

-- Key Mapping
RegisterCommand(Config.OpenCommand or "openadmin", function()
    display = not display
    open(display)
end)

RegisterKeyMapping(Config.OpenCommand or "openadmin", 'Open Admin Menu', 'keyboard', Config.DefaultKey or "F1")

-- Sync on startup and player load
Citizen.CreateThread(function()
    TriggerServerEvent('bk_admin:requestSync')
end)

-- Support both legacy QBCore and QBX client loaded events
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('bk_admin:requestSync')
end)
RegisterNetEvent('qbx_core:client:playerLoaded', function()
    TriggerServerEvent('bk_admin:requestSync')
end)

-- Server -> NUI notify forwarder (ensure small notify shows for server-side messages)
RegisterNetEvent('bk_admin:notify')
AddEventHandler('bk_admin:notify', function(msg)
    if msg then
        SendNUIMessage({ type = "notify", msg = msg })
    end
end)

local hasIgnoredInitialSync = false -- Track if we've already ignored the initial time sync on join

function safeTeleport(coords)
    local playerPed = PlayerPedId()
    local fadeTime = math.floor((Config.Teleport.FadeTime or 0.5) * 1000)
    local loadTime = math.floor((Config.Teleport.LoadTime or 2.0) * 1000)
    
    DoScreenFadeOut(fadeTime)
    while not IsScreenFadedOut() do Citizen.Wait(0) end
    
    if Config.Teleport.InvisibleDuringLoad then SetEntityVisible(playerPed, false, false) end
    SetEntityCoords(playerPed, coords.x, coords.y, coords.z, false, false, false, true)
    
    Citizen.CreateThread(function()
        Citizen.Wait(loadTime)
        if Config.Teleport.InvisibleDuringLoad then SetEntityVisible(playerPed, true, false) end
        DoScreenFadeIn(fadeTime)
        if Config.Teleport.NotifyOnSuccess then SendNUIMessage({ type = "notify", msg = "Teleport successful" }) end
    end)
end

function open(bool)
    display = bool
    updateNuiFocus()
    
    SendNUIMessage({ 
        type = "ui", 
        status = bool, 
        isGod = isGod,
        weathers = Config.DefaultWeathers, 
        times = Config.DefaultTimes,
        presets = Config.TeleportPresets,
        banDurations = Config.Bans.Durations,
        banReasons = Config.Bans.Reasons,
        locales = Locales[Config.Locale],
        settings = {
            colors = Config.Colors,
            position = Config.UIPosition,
            transparency = Config.UITransparency,
            logo = Config.LogoText,
            fadeSpeed = math.floor((Config.FadeSpeed or 0.2) * 1000)
        }
    })
end

-- NoClip Logic with death protection
Citizen.CreateThread(function()
    while true do
        if isNoClip then
            local playerPed = PlayerPedId()
            FreezeEntityPosition(playerPed, true)
            SetEntityCollision(playerPed, false, false)
            
            -- Protection during flight
            SetEntityInvincible(playerPed, true)
            SetPlayerInvincible(PlayerId(), true)
            SetEntityCanBeDamaged(playerPed, false)
            SetEntityHealth(playerPed, 200)

            -- Mouse wheel speed control (241=scroll up, 242=scroll down)
            if IsControlJustPressed(0, 241) then 
                noclipSpeed = math.min(noclipSpeed + (Config.NoClip.SpeedStep or 0.5), Config.NoClip.MaxSpeed)
                if Config.NoClip.ShowSpeedNotify then SendNUIMessage({ type = "notify", msg = "Speed: " .. noclipSpeed }) end
            elseif IsControlJustPressed(0, 242) then 
                noclipSpeed = math.max(noclipSpeed - (Config.NoClip.SpeedStep or 0.5), 0.05)
                if Config.NoClip.ShowSpeedNotify then SendNUIMessage({ type = "notify", msg = "Speed: " .. noclipSpeed }) end
            end

            local x, y, z = table.unpack(GetEntityCoords(playerPed))
            local dx, dy, dz = getCamDirection()
            local h = GetGameplayCamRelativeHeading() + GetEntityHeading(playerPed)
            local rdx, rdy = math.cos(math.rad(h)), math.sin(math.rad(h))
            
            -- Hold SHIFT (21) to temporarily double speed
            local effectiveSpeed = noclipSpeed * (IsControlPressed(0, 21) and 2.0 or 1.0)

            if IsControlPressed(0, 32) then x, y, z = x + effectiveSpeed * dx, y + effectiveSpeed * dy, z + effectiveSpeed * dz end
            if IsControlPressed(0, 33) then x, y, z = x - effectiveSpeed * dx, y - effectiveSpeed * dy, z - effectiveSpeed * dz end
            if IsControlPressed(0, 34) then x = x - effectiveSpeed * rdx; y = y - effectiveSpeed * rdy end
            if IsControlPressed(0, 35) then x = x + effectiveSpeed * rdx; y = y + effectiveSpeed * rdy end
            if IsControlPressed(0, 44) then z = z + effectiveSpeed end -- Q
            if IsControlPressed(0, 38) then z = z - noclipSpeed end -- E

            SetEntityCoordsNoOffset(playerPed, x, y, z, true, true, true)
            SetEntityHeading(playerPed, h)
            Citizen.Wait(0)
        else
            Citizen.Wait(500)
        end
    end
end)

-- Godmode Thread
Citizen.CreateThread(function()
    while true do
        if isGodmode then
            local playerPed = PlayerPedId()
            SetEntityInvincible(playerPed, true)
            SetPlayerInvincible(PlayerId(), true)
            SetEntityCanBeDamaged(playerPed, false)
            SetEntityHealth(playerPed, 200)
            Citizen.Wait(0)
        else
            Citizen.Wait(1000)
        end
    end
end)

-- Density Thread (Optimized Frame-setting)
Citizen.CreateThread(function()
    while true do
        if currentDensity ~= 1.0 then
            SetVehicleDensityMultiplierThisFrame(currentDensity)
            SetPedDensityMultiplierThisFrame(currentDensity)
            SetRandomVehicleDensityMultiplierThisFrame(currentDensity)
            SetParkedVehicleDensityMultiplierThisFrame(currentDensity)
            SetScenarioPedDensityMultiplierThisFrame(currentDensity, currentDensity)
            Citizen.Wait(0) -- Must be set every frame to take effect
        else
            Citizen.Wait(500) -- Idle when default density is active
        end
    end
end)

-- ESP Thread (Names & IDs)
Citizen.CreateThread(function()
    while true do
        if showPlayerIDs and Config.ESP.Enabled then
            local players = GetActivePlayers()
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)
            
            for _, player in ipairs(players) do
                local targetPed = GetPlayerPed(player)
                local targetCoords = GetEntityCoords(targetPed)
                local dist = #(myCoords - targetCoords)
                
                if dist < (Config.ESP.Range or 50.0) then
                    local id = GetPlayerServerId(player)
                    local name = GetPlayerName(player)
                    local text = ("[%s] %s"):format(id, name)
                    
                    -- Highlight local player
                    local color = Config.ESP.Color
                    if targetPed == myPed then
                        text = "[YOU] " .. text
                    end
                    
                    drawText3D(targetCoords.x, targetCoords.y, targetCoords.z + (Config.ESP.VerticalOffset or 1.1), text, color, Config.ESP.Scale)
                end
            end
            Citizen.Wait(0)
        else
            Citizen.Wait(1000)
        end
    end
end)

-- Admin Tag & Duty Thread
Citizen.CreateThread(function()
    while true do
        if isOnDuty and Config.Duty.EnableTag then
            -- Show own tag (only visible to self in admin mode)
            local myCoords = GetEntityCoords(PlayerPedId())
            local tagText = Config.Duty.Tags[currentRank] or "[ADMIN]"
            drawText3D(myCoords.x, myCoords.y, myCoords.z + 1.0, tagText, {r=255,g=255,b=255,a=215}, Config.Duty.TagScale or 0.35)
            Citizen.Wait(0)
        else
            Citizen.Wait(1000)
        end
    end
end)

function drawText3D(x, y, z, text, color, scale)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if onScreen then
        local c = color or {r=255, g=255, b=255, a=215}
        SetTextScale(scale or 0.35, scale or 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(c.r, c.g, c.b, c.a)
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

RegisterNUICallback("adminAction", function(data, cb)
    local playerPed = PlayerPedId()
    if data.action == "noclip" then
        isNoClip = not isNoClip
        if isNoClip then
            SetEntityVisible(playerPed, false, false)
            isInvisible = true
            -- Hide cursor but keep keyboard navigation so Enter can exit NoClip
            SetNuiFocus(true, false)
            SetNuiFocusKeepInput(true)
            if Config.NoClip.ShowSpeedNotify then SendNUIMessage({ type = "notify", msg = "Speed: " .. noclipSpeed }) end
            TriggerServerEvent('bk_admin:logAdminAction', 'NoClip', 'enabled')
        else
            FreezeEntityPosition(playerPed, false)
            SetEntityCollision(playerPed, true, true)
            SetEntityVelocity(playerPed, 0.0, 0.0, 0.0)
            SetEntityInvincible(playerPed, false)
            SetPlayerInvincible(PlayerId(), false)
            updateNuiFocus() -- restore normal focus/cursor based on menu/input state
            TriggerServerEvent('bk_admin:logAdminAction', 'NoClip', 'disabled')
        end
    elseif data.action == "godmode" then
        isGodmode = not isGodmode
        local playerPed = PlayerPedId()
        if isGodmode then
            SetEntityInvincible(playerPed, true)
            SetPlayerInvincible(PlayerId(), true)
            SetEntityCanBeDamaged(playerPed, false)
            SetEntityHealth(playerPed, 200)
            SendNUIMessage({ type = "notify", msg = "Godmode: AN" })
            TriggerServerEvent('bk_admin:logAdminAction', 'Godmode', 'enabled')
        else
            SetEntityInvincible(playerPed, false)
            SetPlayerInvincible(PlayerId(), false)
            SetEntityCanBeDamaged(playerPed, true)
            SendNUIMessage({ type = "notify", msg = "Godmode: AUS" })
            TriggerServerEvent('bk_admin:logAdminAction', 'Godmode', 'disabled')
        end
    elseif data.action == "superadmin" then
        if not isGod then return end
        isSuperAdmin = not isSuperAdmin
        local playerPed = PlayerPedId()
        if isSuperAdmin then
            SetEntityAlpha(playerPed, 0, false)
            SetEntityVisible(playerPed, false, false)
            SendNUIMessage({ type = "notify", msg = "Super-Admin Mode: ON" })
        else
            ResetEntityAlpha(playerPed)
            SetEntityVisible(playerPed, true, false)
            SendNUIMessage({ type = "notify", msg = "Super-Admin Mode: OFF" })
        end
    elseif data.action == "showids" then
        showPlayerIDs = not showPlayerIDs
        SendNUIMessage({ type = "notify", msg = "Spieler IDs: " .. (showPlayerIDs and "AN" or "AUS") })
        TriggerServerEvent('bk_admin:logAdminAction', 'ShowIDs', showPlayerIDs and 'enabled' or 'disabled')
    elseif data.action == "vanish" then
        if not isGod then return end
        isVanished = not isVanished
        local playerPed = PlayerPedId()
        if isVanished then
            SetEntityAlpha(playerPed, 0, false)
            SetEntityVisible(playerPed, false, false)
            SetPlayerInvincible(PlayerId(), true)
            SetEntityCanBeDamaged(playerPed, false)
            SendNUIMessage({ type = "notify", msg = "Super-Vanish Mode: ON" })
            TriggerServerEvent('bk_admin:logAdminAction', 'Vanish', 'enabled')
        else
            ResetEntityAlpha(playerPed)
            SetEntityVisible(playerPed, true, false)
            SetPlayerInvincible(PlayerId(), false)
            SetEntityCanBeDamaged(playerPed, true)
            SendNUIMessage({ type = "notify", msg = "Super-Vanish Mode: OFF" })
            TriggerServerEvent('bk_admin:logAdminAction', 'Vanish', 'disabled')
        end
    elseif data.action == "spawnobject" then
        OpenInput(L('kb_object'), function(model)
            if model and model ~= "" then
                spawnObject(model)
            end
        end, nil, "", 50, "prop_bench_01a")
    elseif data.action == "deleteobject" then
        deleteObject()
    elseif data.action == "massheal" then
        TriggerServerEvent('bk_admin:massAction', 'massheal')
    elseif data.action == "masstele" then
        TriggerServerEvent('bk_admin:massAction', 'masstele')
    elseif data.action == "visibility" then
        isInvisible = not isInvisible
        SetEntityVisible(playerPed, not isInvisible, false)
        TriggerServerEvent('bk_admin:logAdminAction', 'Visibility', isInvisible and 'invisible' or 'visible')
    elseif data.action == "duty" then
        TriggerServerEvent('bk_admin:toggleDuty')
        -- Immediate local feedback for the creator: toggle local state and notify
        isOnDuty = not isOnDuty
        currentRank = currentRank or "admin"
        local statusMsg = "Admin Dienst: " .. (isOnDuty and "AN" or "AUS")
        SendNUIMessage({ type = "notify", msg = statusMsg })
    elseif data.action == "fix" then
        local v = GetVehiclePedIsIn(playerPed, false)
        if v ~= 0 then 
            SetVehicleFixed(v)
            SetVehicleDirtLevel(v, 0.0) 
            SetVehicleDeformationFixed(v)
            if Config.Vehicles.MaxFuelOnSpawn then exports['LegacyFuel']:SetFuel(v, 100.0) end
            SendNUIMessage({ type = "notify", msg = "Fahrzeug repariert & gewaschen" })
            TriggerServerEvent('bk_admin:logAdminAction', 'Fix Vehicle', 'repaired current vehicle')
        end
    elseif data.action == "deletevehicle" then
        local v = GetVehiclePedIsIn(playerPed, false)
        if v ~= 0 then
            if GetPedInVehicleSeat(v, -1) == playerPed then
                local plate = GetVehicleNumberPlateText(v)
                SetEntityAsMissionEntity(v, true, true)
                DeleteVehicle(v)
                SendNUIMessage({ type = "notify", msg = "Fahrzeug gelöscht" })
                TriggerServerEvent('bk_admin:logAdminAction', 'Delete Vehicle', 'deleted vehicle plate '.. tostring(plate))
            else
                SendNUIMessage({ type = "notify", msg = "Du musst Fahrer sein" })
            end
        else
            SendNUIMessage({ type = "notify", msg = "Du sitzt nicht im Fahrzeug" })
        end
    elseif data.action == "telepreset" then
        local preset = Config.TeleportPresets[data.data.cat][data.data.id + 1]
        if preset then
            safeTeleport(preset.coords)
        end
    elseif data.action == "revive" then
        NetworkResurrectLocalPlayer(GetEntityCoords(playerPed), GetEntityHeading(playerPed), true, false)
        SetEntityHealth(playerPed, 200)
        TriggerServerEvent('bk_admin:logAdminAction', 'Revive Self', 'revived self')
    elseif data.action == "copycoords" then
        local coords = GetEntityCoords(playerPed)
        local h = GetEntityHeading(playerPed)
        local str = ""
        if data.data == 'v3' then
            str = string.format("vector3(%.2f, %.2f, %.2f)", coords.x, coords.y, coords.z)
        else
            str = string.format("vector4(%.2f, %.2f, %.2f, %.2f)", coords.x, coords.y, coords.z, h)
        end
        SendNUIMessage({ type = "copyCoords", coords = str })
        SendNUIMessage({ type = "notify", msg = "Coords copied to clipboard" })
    elseif data.action == "setdim" then
        OpenInput(L('kb_dimension'), function(dim)
            if dim and tonumber(dim) then
                local bucket = tonumber(dim)
                TriggerServerEvent('bk_admin:setDimension', bucket)
                SendNUIMessage({ type = "notify", msg = "Dimensionwechsel angefragt: " .. tostring(bucket) })
            end
        end, nil, "0", 5, "0-999")
    elseif data.action == "teleportwaypoint" then
        local blip = GetFirstBlipInfoId(8) -- 8 is the waypoint blip
        if DoesBlipExist(blip) then
            local coords = GetBlipInfoIdCoord(blip)
            
            Citizen.CreateThread(function()
                -- Start teleport to high altitude to allow ground to load
                DoScreenFadeOut(500)
                while not IsScreenFadedOut() do Citizen.Wait(0) end
                
                SetEntityCoords(playerPed, coords.x, coords.y, 1000.0, false, false, false, true)
                FreezeEntityPosition(playerPed, true)
                
                local groundFound = false
                local groundZ = 0.0
                local attempts = 0
                
                while not groundFound and attempts < 100 do
                    Citizen.Wait(50)
                    groundFound, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, 1000.0 - (attempts * 10.0), true)
                    if not groundFound then
                        groundFound, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + (attempts * 1.0), true)
                    end
                    attempts = attempts + 1
                    -- Request collision at the target coords
                    RequestCollisionAtCoord(coords.x, coords.y, groundZ)
                end
                
                if not groundFound then groundZ = coords.z end -- Fallback
                
                safeTeleport(vector3(coords.x, coords.y, groundZ + 1.0))
                FreezeEntityPosition(playerPed, false)
            end)
        end
    elseif data.action == "teleportcoords" then
        OpenInput(L('kb_coords'), function(res)
            if res then
                -- Robustere Regex für verschiedene Formate
                local x, y, z = res:match("([%-?%d%.]+)%s*[,%s]%s*([%-?%d%.]+)%s*[,%s]%s*([%-?%d%.]+)")
                if not x then
                    x, y, z = res:match("vector3%(([%-?%d%.]+)%s*[,%s]%s*([%-?%d%.]+)%s*[,%s]%s*([%-?%d%.]+)%)")
                end
                
                if x and y and z then
                    local tx, ty, tz = tonumber(x), tonumber(y), tonumber(z)
                    if tx and ty and tz then
                        safeTeleport(vector3(tx, ty, tz))
                    end
                end
            end
        end, nil, "", 100, "x, y, z")
    elseif data.action == "blackout" then
        TriggerServerEvent('bk_admin:blackout')
    elseif data.action == "announce" then
        OpenInput(L('kb_announce_title'), function(title)
            if title and title ~= "" then
                OpenInput(L('kb_announce_text'), function(text)
                    if text and text ~= "" then
                        OpenInput(L('kb_announce_duration'), function(duration)
                            local durMs = (tonumber(duration) or 5) * 1000
                            TriggerServerEvent('bk_admin:announce', title, text, durMs)
                            SendNUIMessage({ type = "announcement", title = title or (Config.Announcements and Config.Announcements.Title) or "ANKÜNDIGUNG", text = text or "", duration = durMs or (Config.Announcements and (Config.Announcements.Duration or 5.0) * 1000) or 5000 })
                            SendNUIMessage({ type = "notify", msg = (title or "") ~= "" and (title .. ": " .. (text or "")) or (text or title or "") })
                        end, nil, "5", 3, "5")
                    end
                end, nil, "", 200, "")
            end
        end, nil, "", 30, "")
    elseif data.action == "tunebackend_performance" then
        local v = GetVehiclePedIsIn(playerPed, false)
        if v ~= 0 then
            tuneVehiclePerformance(v)
        else
            SendNUIMessage({ type = "notify", msg = "Du sitzt in keinem Fahrzeug" })
        end
    elseif data.action == "tunebackend_cosmetics" then
        local v = GetVehiclePedIsIn(playerPed, false)
        if v ~= 0 then
            tuneVehicleCosmetics(v)
        else
            SendNUIMessage({ type = "notify", msg = "Du sitzt in keinem Fahrzeug" })
        end
    elseif data.action == "spawnvehicle" then
        OpenInput(L('kb_veh'), function(model)
            if model and model ~= "" then
                spawnVehicle(model)
            end
        end, nil, "", 30, "adder")
    end
    cb('ok')
end)

function setWeather(weather)
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    local seconds = (Config.Weather and Config.Weather.TransitionTime) or 120.0
    SetWeatherTypeOverTime(weather, seconds)
end

function setTime(targetTime)
    local targetHour, targetMinute = targetTime:match("([^:]+):([^:]+)")
    targetHour, targetMinute = tonumber(targetHour), tonumber(targetMinute)
    isTransitioningTime = true
    Citizen.CreateThread(function()
        local currentHour, currentMinute = GetClockHours(), GetClockMinutes()
        local currentTotal = (currentHour * 60) + currentMinute
        local targetTotal = (targetHour * 60) + targetMinute
        if targetTotal < currentTotal then targetTotal = targetTotal + 1440 end
        local diff = targetTotal - currentTotal
        if diff <= 0 then
            NetworkOverrideClockTime(targetHour, targetMinute, 0)
            isTransitioningTime = false
            return
        end
        
        -- Calculate wait time based on seconds from Config
        local totalMs = (Config.Time.TransitionTime or 120.0) * 1000
        local waitTime = math.floor(totalMs / diff)
        if waitTime < (Config.Time.Interval or 10) then waitTime = (Config.Time.Interval or 10) end
        
        for i = 1, diff do
            if not isTransitioningTime then break end
            currentTotal = currentTotal + 1
            NetworkOverrideClockTime(math.floor((currentTotal / 60) % 24), math.floor(currentTotal % 60), 0)
            Citizen.Wait(waitTime)
        end
        isTransitioningTime = false
    end)
end

RegisterNUICallback("setWeatherAndTime", function(data, cb)
    if not data then return cb('ok') end
    
    if data.weather then 
        TriggerServerEvent('bk_admin:setWeather', data.weather)
        local sec = (Config.Weather and Config.Weather.TransitionTime) or 120.0
        local msg
        if Config.Locale == 'de' then
            msg = ("Wetterwechsel: %s (%ds)"):format(tostring(data.weather), math.floor(sec))
        else
            msg = ("Weather: %s (%ds transition)"):format(tostring(data.weather), math.floor(sec))
        end
        SendNUIMessage({ type = "notify", msg = msg })
    elseif data.time then 
        local h, m = tostring(data.time):match("([^:]+):([^:]+)")
        if h and m then
            TriggerServerEvent('bk_admin:setTime', h, m)
            local sec = (Config.Time and Config.Time.TransitionTime) or 120.0
            local msg
            if Config.Locale == 'de' then
                msg = ("Zeitwechsel: %02d:%02d (%ds)"):format(tonumber(h) or 0, tonumber(m) or 0, math.floor(sec))
            else
                msg = ("Time: %02d:%02d (%ds transition)"):format(tonumber(h) or 0, tonumber(m) or 0, math.floor(sec))
            end
            SendNUIMessage({ type = "notify", msg = msg })
        end
    elseif data.waves ~= nil then
        TriggerServerEvent('bk_admin:setWaves', tonumber(data.waves) or 0.0)
    elseif data.density ~= nil then
        currentDensity = tonumber(data.density) or 1.0
        SendNUIMessage({ type = "notify", msg = "NPC Dichte: " .. (currentDensity * 100) .. "%" })
    end
    cb('ok')
end)

-- Server Sync Events
RegisterNetEvent('bk_admin:syncWeather', function(weather)
    -- Only skip the very first sync if auto-sync on start is enabled
    if Config.AutoSyncOnStart and not hasIgnoredInitialSync then
        hasIgnoredInitialSync = true
        return
    end
    setWeather(weather)
end)

RegisterNetEvent('bk_admin:syncTime', function(h, m)
    -- If auto-sync is active on resource start, do one immediate sync, otherwise use transitions
    if Config.AutoSyncOnStart and not hasIgnoredInitialSync then
        hasIgnoredInitialSync = true
        hasSyncedTime = true
        local hh = tonumber(h) or 0
        local mm = tonumber(m) or 0
        NetworkOverrideClockTime(hh, mm, 0)
        return
    end

    local now = GetGameTimer()
    if lastTimeSync ~= 0 and (now - lastTimeSync) < 2000 then return end
    lastTimeSync = now

    if isTransitioningTime then
        isTransitioningTime = false
        Citizen.Wait(50)
    end
    setTime(string.format("%02d:%02d", h, m))
end)

RegisterNUICallback("close", function(data, cb)
    display = false; open(false); cb('ok')
end)

Citizen.CreateThread(function()
    while true do
        local h, m = GetClockHours(), GetClockMinutes()
        SendNUIMessage({ type = "main", time = (h < 10 and "0"..h or h)..":"..(m < 10 and "0"..m or m) })
        Citizen.Wait(1000)
    end
end)
function spawnObject(model)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return end
    RequestModel(hash)
    while not HasModelLoaded(hash) do Citizen.Wait(0) end
    local coords = GetEntityCoords(PlayerPedId())
    local forward = GetEntityForwardVector(PlayerPedId())
    local objCoords = coords + (forward * 2.0)
    local obj = CreateObject(hash, objCoords.x, objCoords.y, objCoords.z, true, true, false)
    PlaceObjectOnGroundProperly(obj)
    SetModelAsNoLongerNeeded(hash)
    table.insert(spawnedObjects, obj)
    TriggerServerEvent('bk_admin:logAdminAction', 'Spawn Object', 'spawned object: ' .. model)
end

function spawnVehicle(model)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return end
    
    RequestModel(hash)
    while not HasModelLoaded(hash) do Citizen.Wait(0) end
    
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)
    SetPedIntoVehicle(playerPed, vehicle, -1)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetModelAsNoLongerNeeded(hash)
    TriggerServerEvent('bk_admin:logAdminAction', 'Spawn Vehicle', 'spawned vehicle: ' .. model)
end

local function ensureModKit(vehicle)
    if GetVehicleModKit(vehicle) ~= 0 then
        SetVehicleModKit(vehicle, 0)
    end
end

function tuneVehiclePerformance(vehicle)
    ensureModKit(vehicle)
    local perfMods = {11, 12, 13, 15, 16} -- engine, brakes, transmission, suspension, armor
    for _, modType in ipairs(perfMods) do
        local max = GetNumVehicleMods(vehicle, modType)
        if max and max > 0 then
            SetVehicleMod(vehicle, modType, max - 1, false)
        end
    end
    ToggleVehicleMod(vehicle, 18, true) -- turbo
    SetVehicleMod(vehicle, 14, -1, false) -- horn back to stock
    SetVehicleMod(vehicle, 22, 0, false) -- lights mod stock (avoid odd behavior)
    SendNUIMessage({ type = "notify", msg = "Performance auf MAX" })
    TriggerServerEvent('bk_admin:logAdminAction', 'Tune Performance', 'max tuned current vehicle')
end

function tuneVehicleCosmetics(vehicle)
    ensureModKit(vehicle)
    -- Cosmetic mod types (skip performance 11,12,13,15,16 and turbo 18)
    local cosmeticMods = {0,1,2,3,4,5,6,7,8,9,10,14,17,19,20,21,23,24,25}
    for _, modType in ipairs(cosmeticMods) do
        local max = GetNumVehicleMods(vehicle, modType)
        if max and max > 0 then
            local pick = math.random(0, max) -- 0 means stock (-1)
            local modIndex = (pick == 0) and -1 or (pick - 1)
            SetVehicleMod(vehicle, modType, modIndex, modType == 23 or modType == 24) -- wheels need custom flag
        end
    end
    -- Random paint
    local primary = math.random(0, 160)
    local secondary = math.random(0, 160)
    SetVehicleColours(vehicle, primary, secondary)
    local pearlescent = math.random(0, 160)
    local wheelColor = math.random(0, 160)
    SetVehicleExtraColours(vehicle, pearlescent, wheelColor)
    -- Random window tint where possible
    local tintOptions = {0,1,2,3,4,5}
    SetVehicleWindowTint(vehicle, tintOptions[math.random(#tintOptions)])
    SendNUIMessage({ type = "notify", msg = "Kosmetik randomisiert" })
    TriggerServerEvent('bk_admin:logAdminAction', 'Tune Cosmetics', 'randomized vehicle cosmetics')
end

function deleteObject()
    if #spawnedObjects == 0 then
        SendNUIMessage({ type = "notify", msg = "Keine gespawnten Objekte vorhanden" })
        return
    end
    
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local closestDist = 100
    local closestIndex = nil
    
    for i, objHandle in ipairs(spawnedObjects) do
        if DoesEntityExist(objHandle) then
            local objPos = GetEntityCoords(objHandle)
            local dist = #(playerPos - objPos)
            if dist < closestDist then
                closestDist = dist
                closestIndex = i
            end
        end
    end
    
    if closestIndex then
        local obj = spawnedObjects[closestIndex]
        SetEntityAsMissionEntity(obj, true, true)
        DeleteEntity(obj)
        table.remove(spawnedObjects, closestIndex)
        SendNUIMessage({ type = "notify", msg = "Objekt gelöscht" })
        TriggerServerEvent('bk_admin:logAdminAction', 'Delete Object', 'deleted spawned object')
    else
        SendNUIMessage({ type = "notify", msg = "Kein Objekt in der Nähe" })
    end
end

RegisterNUICallback("getPlayers", function(data, cb)
    TriggerServerEvent('bk_admin:getPlayers')
    cb('ok')
end)

RegisterNUICallback("playerAction", function(data, cb)
    if data.name then selectedPlayerName = data.name end
    if data.action == "goto" then
        TriggerServerEvent('bk_admin:teleportToPlayer', data.id)
    elseif data.action == "bring" then
        local coords = GetEntityCoords(PlayerPedId())
        TriggerServerEvent('bk_admin:bringPlayer', data.id, coords)
    elseif data.action == "heal" then
        TriggerServerEvent('bk_admin:playerAction', data.id, "heal")
    elseif data.action == "revive" then
        TriggerServerEvent('bk_admin:playerAction', data.id, "revive")
    elseif data.action == "kick" then
        OpenInput(L('kb_kick_reason'), function(reason)
            if reason and reason ~= "" then
                TriggerServerEvent('bk_admin:playerAction', data.id, "kick", reason)
            end
        end, data.id, "", 100, "")
    elseif data.action == "ban" then
        SendNUIMessage({ type = "openSub", sub = "playerBanReasonSub" })
    elseif data.action == "selectreason" then
        selectedBanReason = Config.BanReasons[data.data + 1]
        SendNUIMessage({ type = "openSub", sub = "playerBanDurationSub" })
    elseif data.action == "customreason" then
        OpenInput(L('kb_reason'), function(reason)
            selectedBanReason = reason
            if selectedBanReason and selectedBanReason ~= "" then
                SendNUIMessage({ type = "openSub", sub = "playerBanDurationSub" })
            end
        end, nil, "", 100, "")
    elseif data.action == "selectduration" then
        selectedBanDuration = tostring(Config.BanDurations[data.data + 1].days)
        SendNUIMessage({ 
            type = "confirmBan", 
            targetId = data.id, 
            targetName = selectedPlayerName or "Spieler", 
            reason = selectedBanReason, 
            duration = selectedBanDuration 
        })
    elseif data.action == "customban" then
        OpenInput(L('kb_ban_duration'), function(duration)
            selectedBanDuration = duration
            if selectedBanDuration and selectedBanDuration ~= "" then
                SendNUIMessage({ 
                    type = "confirmBan", 
                    targetId = data.id, 
                    targetName = selectedPlayerName or "Spieler", 
                    reason = selectedBanReason, 
                    duration = selectedBanDuration 
                })
            end
        end, data.id, "", 20, "0")
    elseif data.action == "privatemessage" then
        OpenInput(L('kb_msg_title'), function(title)
            if title and title ~= "" then
                OpenInput(L('kb_msg_text'), function(text)
                    if text and text ~= "" then
                        TriggerServerEvent('bk_admin:privateMessage', data.id, title, text)
                    end
                end, data.id, "", 200, "")
            end
        end, data.id, "", 30, "")
    elseif data.action == "freeze" then
        TriggerServerEvent('bk_admin:playerAction', data.id, "freeze")
    elseif data.action == "spectate" then
        TriggerServerEvent('bk_admin:playerAction', data.id, "spectate")
    elseif data.action == "inventory" then
        TriggerServerEvent('bk_admin:playerAction', data.id, "inventory")
    elseif data.action == "giveitem" then
        OpenInput(L('kb_item'), function(item)
            if item and item ~= "" then
                TriggerServerEvent('bk_admin:playerAction', data.id, "giveitem", item)
            end
        end, data.id, "", 30, "")
    elseif data.action == "setjob" then
        OpenInput(L('kb_job_name'), function(job)
            if job and job ~= "" then
                OpenInput(L('kb_job_grade'), function(grade)
                    TriggerServerEvent('bk_admin:setJob', data.id, job, tonumber(grade) or 0)
                end, data.id, "0", 5, "0")
            end
        end, data.id, "", 30, "police")
    elseif data.action == "addnote" then
        OpenInput(L('kb_note'), function(note)
            if note and note ~= "" then
                TriggerServerEvent('bk_admin:addNote', { id = data.id, note = note })
            end
        end, data.id, "", 200, "")
    elseif data.action == "setrank" then
        if not isGod then return end
        TriggerServerEvent('bk_admin:setRank', data.id, data.data)
        backToPlayerActionsMain()
    elseif data.action == "givemoney" then
        OpenInput(L('kb_money'), function(amount)
            if amount and tonumber(amount) then
                TriggerServerEvent('bk_admin:playerAction', data.id, "givemoney", tonumber(amount))
            end
        end, data.id, "", 10, "1000")
    elseif data.action == "removemoney" then
        OpenInput(L('kb_money'), function(amount)
            if amount and tonumber(amount) then
                TriggerServerEvent('bk_admin:playerAction', data.id, "removemoney", tonumber(amount))
            end
        end, data.id, "", 10, "1000")
    elseif data.action == "giveweapon" then
        OpenInput(L('kb_weapon'), function(weapon)
            if weapon and weapon ~= "" then
                TriggerServerEvent('bk_admin:playerAction', data.id, "giveweapon", weapon)
            end
        end, data.id, "", 30, "WEAPON_PISTOL")
    elseif data.action == "removeweapons" then
        TriggerServerEvent('bk_admin:playerAction', data.id, "removeweapons")
    end
    cb('ok')
end)

RegisterNetEvent('bk_admin:notify', function(msg)
    SendNUIMessage({ type = "notify", msg = msg })
end)

RegisterNetEvent('bk_admin:clientAction', function(action, data)
    local playerPed = PlayerPedId()
    if action == "heal" then
        SetEntityHealth(playerPed, 200)
        SetPlayerMaxArmour(PlayerId(), 100)
        SetPedArmour(playerPed, 100)
    elseif action == "revive" then
        NetworkResurrectLocalPlayer(GetEntityCoords(playerPed), GetEntityHeading(playerPed), true, false)
        SetEntityHealth(playerPed, 200)
    elseif action == "freeze" then
        -- Toggle freeze on self
        local playerPed = PlayerPedId()
        FreezeEntityPosition(playerPed, not IsEntityPositionFrozen(playerPed))
    elseif action == "spectate" then
        if not isSpectating then
            local targetPed = GetPlayerPed(GetPlayerFromServerId(data))
            spectateTarget = data
            isSpectating = true
            NetworkSetInSpectatorMode(true, targetPed)
        else
            isSpectating = false
            NetworkSetInSpectatorMode(false, playerPed)
            spectateTarget = nil
        end
    elseif action == "inventory" then
        -- Inventory opening is handled by server-side trigger now
        -- Nothing to do on client
    elseif action == "giveweapon" then
        GiveWeaponToPed(playerPed, GetHashKey(data), 250, false, true)
    elseif action == "removeweapons" then
        RemoveAllPedWeapons(playerPed, true)
    elseif action == "giveitem" then
        -- Hier müsste die Framework-Logik rein (ESX, QB-Core, etc.)
        -- Item handling executed (no debug print)
    end
end)

RegisterNetEvent('bk_admin:safeTeleport', function(coords)
    safeTeleport(coords)
end)

RegisterNetEvent('bk_admin:clientSyncDuty', function(state, rank)
    isOnDuty = state
    currentRank = rank or "admin"
    local playerPed = PlayerPedId()
    if isOnDuty then
        if Config.Duty.EnablePedSwitch then
            local modelName = Config.Duty.Models[currentRank]
            if modelName then
                local model = GetHashKey(modelName)
                RequestModel(model)
                while not HasModelLoaded(model) do Citizen.Wait(0) end
                originalModel = GetEntityModel(playerPed)
                SetPlayerModel(PlayerId(), model)
                SetModelAsNoLongerNeeded(model)
            end
        end
    else
        if originalModel then
            -- Back to original (usually requires framework character reset)
            TriggerEvent('qb-clothes:client:CreateFirstCharacter') -- QBX Example
        end
    end
end)

RegisterNetEvent('bk_admin:clientCleanup', function()
    -- This event is now mostly handled server-side for better reliability
    -- but we keep a local small cleanup for non-networked entities
    local playerPed = PlayerPedId()
    local currentVehicle = GetVehiclePedIsIn(playerPed, false)
    
    local vehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(vehicles) do
        if vehicle ~= currentVehicle and not IsPedAPlayer(GetPedInVehicleSeat(vehicle, -1)) then
            SetEntityAsMissionEntity(vehicle, false, false)
            DeleteVehicle(vehicle)
        end
    end
end)

RegisterNetEvent('bk_admin:syncBlackout', function(state)
    SetBlackout(state)
end)

RegisterNetEvent('bk_admin:syncWaves', function(intensity)
    SetWavesIntensity(intensity)
end)

-- Helper für Entity Enumeration
local entityEnumerators = {
    ['Vehicles'] = {GetFirstVehicle, GetNextVehicle, EndFindVehicle},
    ['Peds'] = {GetFirstPed, GetNextPed, EndFindPed},
    ['Objects'] = {GetFirstObject, GetNextObject, EndFindObject},
    ['Pickups'] = {GetFirstPickup, GetNextPickup, EndFindPickup}
}

function EnumerateEntities(type)
    return coroutine.wrap(function()
        local iter, getter, ending = table.unpack(entityEnumerators[type])
        local handle, entity = iter()
        local success
        if not handle or handle == -1 then ending(handle); return end
        repeat
            coroutine.yield(entity)
            success, entity = getter(handle)
        until not success
        ending(handle)
    end)
end

function EnumerateVehicles() return EnumerateEntities('Vehicles') end
function EnumerateObjects() return EnumerateEntities('Objects') end

RegisterNetEvent('bk_admin:showAnnouncement', function(title, text, duration)
    local dur = duration or math.floor((Config.Announcements.Duration or 5.0) * 1000)
    SendNUIMessage({ type = "announcement", title = title, text = text, duration = dur })
    -- Also push a small toast via NUI for quick glance
    local toast = (title and text) and (title .. ": " .. text) or (text or title or "")
    if toast ~= "" then
        SendNUIMessage({ type = "notify", msg = toast })
    end
end)

local isVanished = false

RegisterNetEvent('bk_admin:syncGodStatus', function(state)
    isGod = state
end)

RegisterNetEvent('bk_admin:receiveItems', function(items)
    if items then SendNUIMessage({ type = "items", items = items }) end
end)

RegisterNetEvent('bk_admin:receiveBans', function(bans)
    SendNUIMessage({ type = "bans", bans = bans })
end)

RegisterNetEvent('bk_admin:receiveHistory', function(history)
    if history and history[1] then
        local h = history[1]
        SendNUIMessage({ 
            type = "playerInfo", 
            rank = h.rank, 
            citizenid = h.citizenid, 
            last_seen = h.last_seen 
        })
    end
end)

RegisterNetEvent('bk_admin:receiveNotes', function(notes)
    SendNUIMessage({ type = "notes", notes = notes })
end)

RegisterNetEvent('bk_admin:receivePlayers', function(players)
    SendNUIMessage({ type = "players", players = players })
end)

RegisterNetEvent('bk_admin:teleportToCoords', function(coords)
    local playerPed = PlayerPedId()
    SetEntityCoords(playerPed, coords.x, coords.y, coords.z, false, false, false, true)
end)

RegisterNUICallback("confirmBan", function(data, cb)
    TriggerServerEvent('bk_admin:confirmBan', data)
    cb('ok')
end)

RegisterNUICallback("serverAction", function(data, cb)
    TriggerServerEvent('bk_admin:serverAction', data)
    cb('ok')
end)

RegisterNUICallback("getBans", function(data, cb)
    TriggerServerEvent('bk_admin:getBans')
    cb('ok')
end)

RegisterNUICallback("getNotes", function(data, cb)
    TriggerServerEvent('bk_admin:getNotes', data)
    cb('ok')
end)

RegisterNUICallback("getPlayerInfo", function(data, cb)
    TriggerServerEvent('bk_admin:getHistory', data.id)
    cb('ok')
end)

-- Generic Input Handler
RegisterNUICallback("handleInput", function(data, cb)
    cb('ok')
    if pendingInputCallback then
        pendingInputCallback(data.input, pendingInputData)
        pendingInputCallback = nil
        pendingInputData = nil
    end
    inputActive = false
    updateNuiFocus()
end)

-- Track input focus state to disable controls when typing
RegisterNUICallback("setInputState", function(data, cb)
    inputActive = data and data.active == true
    updateNuiFocus()
    cb('ok')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if display then open(false) end
    if isNoClip then
        local playerPed = PlayerPedId()
        FreezeEntityPosition(playerPed, false)
        SetEntityCollision(playerPed, true, true)
        SetEntityInvincible(playerPed, false)
    end
end)
