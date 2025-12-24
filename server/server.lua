local CurrentWeather = "EXTRASUNNY"
local CurrentTimeHour = 12
local CurrentTimeMinute = 0
local BlackoutActive = false

-- Resource Name Protection
local REQ_NAME = "bk_admin"
if GetCurrentResourceName() ~= REQ_NAME then
    print("^1[ERROR] bk_admin: Resource name has been changed!^7")
    print(("^1[ERROR] Expected: ^5%s^1 | Actual: ^5%s^7"):format(REQ_NAME, GetCurrentResourceName()))
    print("^1[ERROR] Stopping resource to prevent errors...^7")
    Citizen.CreateThread(function()
        Citizen.Wait(1000)
        StopResource(GetCurrentResourceName())
    end)
    return
end

-- Wait for MySQL to be ready
local MySQL = exports.oxmysql

local qbx = exports.qbx_core

function logToDiscord(name, message, category)
    if not (Config.Logs and Config.Logs.Enabled) then return end
    if not Config.Logs.WebhookURL or Config.Logs.WebhookURL == "your_webhook_url_here" then return end
    -- Check category if provided
    if category and Config.Logs.Categories and Config.Logs.Categories[category] == false then return end
    local embeds = {{
        ["title"] = name,
        ["description"] = message,
        ["type"] = "rich",
        ["color"] = (Config.Logs.Color or 3832997),
        ["footer"] = { ["text"] = os.date("%Y-%m-%d %H:%M:%S") },
    }}
    PerformHttpRequest(Config.Logs.WebhookURL, function(err, text, headers) end, 'POST', json.encode({username = (Config.Logs.BotName or "bk_admin Logs"), embeds = embeds}), { ['Content-Type'] = 'application/json' })
end

-- Unified client notify: sends framework notify only if enabled and always sends our NUI notify
local function clientNotify(target, msg, msgType)
    if Config.UseFrameworkNotify then
    TriggerClientEvent('ox_lib:notify', target, {
        description = msg,
        type = msgType or 'info'
    })
end
    -- Strip GTA color codes (e.g. ^1, ^2, ^7) before sending to NUI notify
    if msg then
        local plain = tostring(msg):gsub("%^.", "")
        TriggerClientEvent('bk_admin:notify', target, plain)
    else
        TriggerClientEvent('bk_admin:notify', target, msg)
    end
end

-- Duty Toggle
RegisterNetEvent('bk_admin:toggleDuty', function()
    local src = source
    if not hasPermission(src) then return end
    local Player = qbx:GetPlayer(src)
    if Player then
        local onDuty = not Player.PlayerData.job.onduty
        Player.Functions.SetJobDuty(onDuty)
        
        -- Determine highest rank for model selection
        local rank = 'admin'
        if qbx:HasPermission(src, 'god') then rank = 'god' end
        
        -- Sync for client tag & model
        TriggerClientEvent('bk_admin:clientSyncDuty', src, onDuty, rank)
        
        local status = onDuty and "^2On Duty^7" or "^1Off Duty^7"
        clientNotify(src, "Admin Duty: " .. status, "success")
        logToDiscord("Admin Duty", ("Admin **%s** (ID %s) is now **%s** (Rank: %s)"):format(GetPlayerName(src), src, onDuty and "ON DUTY" or "OFF DUTY", rank:upper()), "AdminActions")
    end
end)

-- Hourly Ban-Cleanup Thread
Citizen.CreateThread(function()
    Citizen.Wait(5000) -- Initial wait for DB stability
    while true do
        MySQL:query('DELETE FROM bans WHERE expire < ? AND expire != 2147483647', {os.time()}, function(result)
            if result and result.affectedRows > 0 then
                    -- expired bans deleted; no console output needed in production
                end
        end)
        Citizen.Wait((Config.Bans and Config.Bans.CleanupInterval) or 3600000)
    end
end)

-- Check for bans on connecting
AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src = source
    local license = "N/A"
    for k, v in ipairs(GetPlayerIdentifiers(src)) do
        if string.sub(v, 1, string.len("license:")) == "license:" then license = v break end
    end

    deferrals.defer()
    Citizen.Wait(50)
    deferrals.update("Checking Ban Status...")

    MySQL:single('SELECT reason FROM bans WHERE license = ?', {license}, function(result)
        if result then
            deferrals.done("You are banned from this server. Reason: " .. result.reason)
        else
            deferrals.done()
        end
    end)
end)

-- Get Notes
RegisterNetEvent('bk_admin:getNotes', function(data)
    local src = source
    if not hasPermission(src) then return end
    local targetPlayer = qbx:GetPlayer(data.id)
    if not targetPlayer then return end
    
    MySQL:query('SELECT author, note, date FROM bk_admin_notes WHERE citizenid = ? ORDER BY id DESC', {targetPlayer.PlayerData.citizenid}, function(notes)
        TriggerClientEvent('bk_admin:receiveNotes', src, notes)
    end)
end)

-- Add Note
RegisterNetEvent('bk_admin:addNote', function(data)
    local src = source
    if not hasPermission(src) then return end
    local targetPlayer = qbx:GetPlayer(data.id)
    if not targetPlayer then return end
    
    local adminName = GetPlayerName(src)
    local date = os.date("%Y-%m-%d %H:%M")
    
    MySQL:insert('INSERT INTO bk_admin_notes (citizenid, note, author, date) VALUES (?, ?, ?, ?)', {
        targetPlayer.PlayerData.citizenid, data.note, adminName, date
    }, function(id)
        if id then
            clientNotify(src, "Notiz hinzugefuegt", "success")
            -- Refresh notes list
            MySQL:query('SELECT author, note, date FROM bk_admin_notes WHERE citizenid = ? ORDER BY id DESC', {targetPlayer.PlayerData.citizenid}, function(notes)
                TriggerClientEvent('bk_admin:receiveNotes', src, notes)
            end)
        end
    end)
end)

-- Set Rank (God only)
RegisterNetEvent('bk_admin:setRank', function(targetId, rank)
    local src = source
    if not qbx:HasPermission(src, 'god') then return end
    
    local targetPlayer = qbx:GetPlayer(targetId)
    if not targetPlayer then return end
    
    local citizenid = targetPlayer.PlayerData.citizenid
    local identifiers = json.encode(GetPlayerIdentifiers(targetId))
    
    -- Update permissions in QBX
    if rank == "user" then
        -- In QBX permissions are removed by setting to a lower level or clearing
        ExecuteCommand(('removepermission %s'):format(targetId))
    else
        ExecuteCommand(('addpermission %s %s'):format(targetId, rank))
    end

    -- Permanent storage in bk_admin table
    MySQL:query('INSERT INTO bk_admin (citizenid, rank, identifiers, last_seen) VALUES (?, ?, ?, NOW()) ON DUPLICATE KEY UPDATE rank = ?, identifiers = ?, last_seen = NOW()', {
        citizenid, rank, identifiers, rank, identifiers
    }, function()
        clientNotify(src, ("Rang von %s auf %s gesetzt"):format(GetPlayerName(targetId), rank:upper()), "success")
        logToDiscord("Rank Update", ("God **%s** set rank of **%s** to **%s**"):format(GetPlayerName(src), GetPlayerName(targetId), rank:upper()), "PlayerActions")
    end)
end)

-- Auto-Restore Permissions on Login
AddEventHandler('qbx_core:server:onPlayerLoaded', function(Player)
    local src = Player.PlayerData.source
    local citizenid = Player.PlayerData.citizenid
    
    MySQL:single('SELECT rank FROM bk_admin WHERE citizenid = ?', {citizenid}, function(result)
        if result and result.rank ~= "user" then
            ExecuteCommand(('addpermission %s %s'):format(src, result.rank))
        end
    end)
end)

-- Set Job
RegisterNetEvent('bk_admin:setJob', function(targetId, job, grade)
    local src = source
    if not hasPermission(src) then return end
    
    -- QBX set job via player Functions API
    local targetPlayer = qbx:GetPlayer(targetId)
    if targetPlayer then
        local ok = pcall(function()
            targetPlayer.Functions.SetJob(job, grade)
        end)
        if ok then
            clientNotify(src, ("Job set for %s to %s (Grade %s)"):format(GetPlayerName(targetId), job, grade), "success")
            logToDiscord("Job Update", ("Admin **%s** set job of **%s** to **%s (Grade %s)**"):format(GetPlayerName(src), GetPlayerName(targetId), job, grade), "PlayerActions")
        else
            clientNotify(src, "Error setting job (invalid job or grade)", "error")
        end
    else
        clientNotify(src, "Target player not found", "error")
    end
end)

-- Get Bans
RegisterNetEvent('bk_admin:getBans', function()
    local src = source
    if not hasPermission(src) then return end
    
    MySQL:query('SELECT name, license, reason, expire FROM bans', {}, function(bans)
        if bans then
            for _, b in ipairs(bans) do
                b.expire_text = b.expire == 2147483647 and "Permanent" or os.date("%Y-%m-%d %H:%M", b.expire)
            end
        end
        TriggerClientEvent('bk_admin:receiveBans', src, bans)
    end)
end)

-- Server Actions (Unban, Mass Heal, Mass Teleport)
RegisterNetEvent('bk_admin:serverAction', function(data)
    local src = source
    if not hasPermission(src) then return end
    
    if data.action == "unban" then
        MySQL:query('DELETE FROM bans WHERE license = ?', {data.data}, function()
            clientNotify(src, "Spieler entbannt", "success")
            logToDiscord("Unban", ("Admin **%s** hat Lizenz **%s** entbannt"):format(GetPlayerName(src), data.data), "PlayerActions")
            -- Refresh list
            TriggerEvent('bk_admin:getBans')
        end)
    end
end)

-- Mass Actions
RegisterNetEvent('bk_admin:massAction', function(action)
    local src = source
    if not hasPermission(src) then return end
    
    local coords = GetEntityCoords(GetPlayerPed(src))
    
    if action == "massheal" then
        TriggerClientEvent('bk_admin:clientAction', -1, "heal")
        clientNotify(src, "Alle Spieler geheilt", "success")
        logToDiscord("Mass Heal", ("Admin **%s** healed all players"):format(GetPlayerName(src)), "ServerActions")
    elseif action == "masstele" then
        TriggerClientEvent('bk_admin:safeTeleport', -1, coords)
        clientNotify(src, "Alle Spieler zu dir teleportiert", "success")
        logToDiscord("Mass Teleport", ("Admin **%s** teleported all players to their location"):format(GetPlayerName(src)), "ServerActions")
    end
end)

-- Get Admin History (Targeted or All)
RegisterNetEvent('bk_admin:getHistory', function(targetId)
    local src = source
    if not hasPermission(src) then return end
    
    local query = [[
        SELECT bk_admin.citizenid, bk_admin.rank, players.charinfo, bk_admin.last_seen
        FROM bk_admin
        LEFT JOIN players ON bk_admin.citizenid COLLATE utf8mb4_unicode_ci = players.citizenid COLLATE utf8mb4_unicode_ci
    ]]
    local params = {}
    
    if targetId then
        local targetPlayer = qbx:GetPlayer(targetId)
        if targetPlayer then
            query = query .. ' WHERE bk_admin.citizenid COLLATE utf8mb4_unicode_ci = ?'
            table.insert(params, targetPlayer.PlayerData.citizenid)
        end
    end
    
    MySQL:query(query, params, function(history)
        if history then
            for _, h in ipairs(history) do
                if h.charinfo then
                    local info = json.decode(h.charinfo)
                    h.name = info.firstname .. " " .. info.lastname
                else
                    h.name = "Unknown"
                end
            end
        end
        TriggerClientEvent('bk_admin:receiveHistory', src, history)
    end)
end)

-- Initial sync when player joins (only if AutoSyncOnStart is enabled)
RegisterNetEvent('bk_admin:requestSync', function()
    local src = source
    local isGod = qbx:HasPermission(src, 'god')
    
    -- Sync Items for Admin
    local items = {}
    if isGod or qbx:HasPermission(src, 'admin') then
        local ok, qbxItems = pcall(function() return exports.qbx_core:GetItems() end)
        if ok and qbxItems then
            for k, v in pairs(qbxItems) do
                table.insert(items, { name = k, label = v.label })
            end
        end
    end

    -- Only sync time/weather if AutoSyncOnStart is enabled
    if Config.AutoSyncOnStart then
        TriggerClientEvent('bk_admin:syncWeather', src, CurrentWeather)
        TriggerClientEvent('bk_admin:syncTime', src, CurrentTimeHour, CurrentTimeMinute)
        TriggerClientEvent('bk_admin:syncBlackout', src, BlackoutActive)
    end
    
    TriggerClientEvent('bk_admin:syncGodStatus', src, isGod, items)
end)

function hasPermission(src)
    -- First, try framework permission checks (QBX)
    if qbx and qbx.HasPermission then
        for perm, _ in pairs(Config.Permissions) do
            if qbx:HasPermission(src, perm) then
                return true
            end
        end
    end

    -- Next, check Config.TrustedServerIds mapping: Config.TrustedServerIds[serverId] = "admin"|"god"
    if Config.TrustedServerIds and type(Config.TrustedServerIds) == 'table' then
        local mapped = Config.TrustedServerIds[src]
        if mapped and Config.Permissions[mapped] then
            return true
        end
    end

    -- Lastly, check license mapping: Config.TrustedLicenses["license:..."] = "admin"|"god"
    if Config.TrustedLicenses and type(Config.TrustedLicenses) == 'table' then
        local ids = GetPlayerIdentifiers(src) or {}
        for _, v in ipairs(ids) do
            local mapped = Config.TrustedLicenses[v]
            if mapped and Config.Permissions[mapped] then
                return true
            end
        end
    end

    return false
end

-- Weather Change
RegisterNetEvent('bk_admin:setWeather', function(weather)
    if not hasPermission(source) then return end
    CurrentWeather = weather
    TriggerClientEvent('bk_admin:syncWeather', -1, CurrentWeather)
    logToDiscord("Weather Changed", ("Admin **%s** set weather to **%s**"):format(GetPlayerName(source), weather), "WorldActions")
end)

-- Time Change
RegisterNetEvent('bk_admin:setTime', function(hour, minute)
    if not hasPermission(source) then return end
    CurrentTimeHour = tonumber(hour)
    CurrentTimeMinute = tonumber(minute)
    TriggerClientEvent('bk_admin:syncTime', -1, CurrentTimeHour, CurrentTimeMinute)
    logToDiscord("Time Changed", ("Admin **%s** set time to **%02d:%02d**"):format(GetPlayerName(source), CurrentTimeHour, CurrentTimeMinute), "WorldActions")
end)

-- Get Player List
local WarnsCache = { map = {}, last = 0 }

RegisterNetEvent('bk_admin:getPlayers', function()
    local src = source
    if not hasPermission(src) then return end
    
    local players = {}
    local rawPlayers = GetPlayers()
    
    local function assembleAndSend(warnMap)
        for _, playerId in ipairs(rawPlayers) do
            local Player = qbx:GetPlayer(playerId)
            if Player then
                table.insert(players, {
                    id = playerId,
                    name = GetPlayerName(playerId),
                    warns = (warnMap and warnMap[Player.PlayerData.citizenid]) or 0
                })
            end
        end
        TriggerClientEvent('bk_admin:receivePlayers', src, players)
    end

    local now = os.time()
    if WarnsCache.last ~= 0 and (now - WarnsCache.last) < 60 then
        assembleAndSend(WarnsCache.map)
        return
    end

    MySQL:query('SELECT citizenid, COUNT(*) as count FROM bk_admin_notes GROUP BY citizenid', {}, function(warns)
        local warnMap = {}
        if warns then
            for _, w in ipairs(warns) do warnMap[w.citizenid] = w.count end
        end
        WarnsCache = { map = warnMap, last = os.time() }
        assembleAndSend(warnMap)
    end)
end)

-- Teleport to Player
RegisterNetEvent('bk_admin:teleportToPlayer', function(targetId)
    local src = source
    if not hasPermission(src) then return end
    local targetPed = GetPlayerPed(targetId)
    if DoesEntityExist(targetPed) then
        local coords = GetEntityCoords(targetPed)
        TriggerClientEvent('bk_admin:safeTeleport', src, coords)
        logToDiscord("Teleport To Player", ("Admin **%s** teleported to **%s** (ID %s)"):format(GetPlayerName(src), GetPlayerName(targetId), targetId), "PlayerActions")
    end
end)

-- Bring Player to self
RegisterNetEvent('bk_admin:bringPlayer', function(targetId, coords)
    local src = source
    if not hasPermission(src) then return end
    TriggerClientEvent('bk_admin:safeTeleport', targetId, coords)
    logToDiscord("Bring Player", ("Admin **%s** brought **%s** (ID %s) to their location"):format(GetPlayerName(src), GetPlayerName(targetId), targetId), "PlayerActions")
end)

-- General Player Actions (Heal, Revive, Item, Money, Weapons, Kick, Ban, Freeze, Spectate)
RegisterNetEvent('bk_admin:playerAction', function(targetId, action, data)
    local src = source
    if not hasPermission(src) then return end
    
    local targetPlayer = qbx:GetPlayer(targetId)
    if not targetPlayer then return end

    if action == "inventory" then
        -- Open target player's inventory for the admin (source)
        TriggerClientEvent('bk_admin:clientAction', src, action, {
            type = 'otherplayer',
            id = targetId,
            name = GetPlayerName(targetId)
        })
        logToDiscord("Open Inventory", ("Admin **%s** opened inventory of **%s** (ID %s)"):format(GetPlayerName(src), GetPlayerName(targetId), targetId), "PlayerActions")
    elseif action == "givemoney" then
        targetPlayer.Functions.AddMoney('cash', data, "Admin Give")
        logToDiscord("Give Money", ("Admin **%s** gave **$%s** to **%s** (ID %s)"):format(GetPlayerName(src), data, GetPlayerName(targetId), targetId), "PlayerActions")
    elseif action == "removemoney" then
        targetPlayer.Functions.RemoveMoney('cash', data, "Admin Remove")
        logToDiscord("Remove Money", ("Admin **%s** removed **$%s** from **%s** (ID %s)"):format(GetPlayerName(src), data, GetPlayerName(targetId), targetId), "PlayerActions")
    elseif action == "giveitem" then
        targetPlayer.Functions.AddItem(data, 1)
        logToDiscord("Give Item", ("Admin **%s** gave item **%s** to **%s** (ID %s)"):format(GetPlayerName(src), data, GetPlayerName(targetId), targetId), "PlayerActions")
    elseif action == "revive" then
        TriggerClientEvent('hospital:client:Revive', targetId)
        logToDiscord("Revive Player", ("Admin **%s** revived **%s** (ID %s)"):format(GetPlayerName(src), GetPlayerName(targetId), targetId), "PlayerActions")
    elseif action == "heal" then
        TriggerClientEvent('bk_admin:clientAction', targetId, action, data)
        logToDiscord("Heal Player", ("Admin **%s** healed **%s** (ID %s)"):format(GetPlayerName(src), GetPlayerName(targetId), targetId), "PlayerActions")
    elseif action == "freeze" then
        TriggerClientEvent('bk_admin:clientAction', targetId, action, data)
        logToDiscord("Freeze Player", ("Admin **%s** toggled freeze on **%s** (ID %s)"):format(GetPlayerName(src), GetPlayerName(targetId), targetId), "PlayerActions")
    elseif action == "spectate" then
        TriggerClientEvent('bk_admin:clientAction', src, action, targetId)
        logToDiscord("Spectate Player", ("Admin **%s** is spectating **%s** (ID %s)"):format(GetPlayerName(src), GetPlayerName(targetId), targetId), "AdminActions")
    elseif action == "giveweapon" then
        TriggerClientEvent('bk_admin:clientAction', targetId, action, data)
        logToDiscord("Give Weapon", ("Admin **%s** gave weapon **%s** to **%s** (ID %s)"):format(GetPlayerName(src), data, GetPlayerName(targetId), targetId), "PlayerActions")
    elseif action == "removeweapons" then
        TriggerClientEvent('bk_admin:clientAction', targetId, action, data)
        logToDiscord("Remove Weapons", ("Admin **%s** removed all weapons from **%s** (ID %s)"):format(GetPlayerName(src), GetPlayerName(targetId), targetId), "PlayerActions")
    elseif action == "kick" then
        logToDiscord("Player Kick", ("Admin **%s** kicked **%s** (ID %s). Reason: %s"):format(GetPlayerName(src), GetPlayerName(targetId), targetId, data or "No reason"), "PlayerActions")
        DropPlayer(targetId, data or "Kicked by Admin")
        return -- Don't trigger client action for kick since player is dropped
    end
    
    -- Only trigger client for actions that need client handling (not kick)
    if action ~= "kick" and action ~= "heal" and action ~= "freeze" and action ~= "spectate" and action ~= "giveweapon" and action ~= "removeweapons" then
        TriggerClientEvent('bk_admin:clientAction', targetId, action, data)
    end
end)

RegisterNetEvent('bk_admin:confirmBan', function(data)
    local src = source
    if not hasPermission(src) then return end
    
    local targetId = data.targetId
    local targetName = GetPlayerName(targetId)
    local reason = data.reason
    local durationString = data.duration -- Can be "2025-12-24 18:00" or "0"
    local adminName = GetPlayerName(src)
    
    local expire = 2147483647 -- Permanent
    local durText = "permanent"

    -- Check if date or days
    if durationString and durationString ~= "0" then
        if string.match(durationString, "%d%d%d%d%-%d%d%-%d%d") then
            -- Date Format (YYYY-MM-DD HH:MM)
            local y, m, d, h, min = string.match(durationString, "(%d+)-(%d+)-(%d+)%s*(%d*):*(%d*)")
            expire = os.time({year=y, month=m, day=d, hour=tonumber(h) or 0, min=tonumber(min) or 0})
            durText = durationString
        else
            -- Days Format
            local days = tonumber(durationString) or 0
            if days > 0 then
                expire = os.time() + (days * 86400)
                durText = days .. " Days"
            end
        end
    end

    -- Collect identifiers
    local license, discord, ip = "N/A", "N/A", GetPlayerEndpoint(targetId)
    for k, v in ipairs(GetPlayerIdentifiers(targetId)) do
        if string.sub(v, 1, string.len("license:")) == "license:" then license = v
        elseif string.sub(v, 1, string.len("discord:")) == "discord:" then discord = v end
    end

    -- Save to DB
    MySQL.insert('INSERT INTO bans (name, license, discord, ip, reason, bannedby, expire) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        targetName, license, discord, ip, reason, adminName, expire
    }, function(id)
        if id then
            clientNotify(src, "Player successfully banned (ID: " .. id .. ")", "success")
        end
    end)
    
    logToDiscord("Player Ban", ("Admin **%s** banned **%s**.\n**Duration:** %s\n**Reason:** %s"):format(adminName, targetName, durText, reason), "PlayerActions")
    DropPlayer(targetId, ("You have been banned. Duration: %s. Reason: %s"):format(durText, reason))
end)

-- World Actions
RegisterNetEvent('bk_admin:blackout', function()
    local src = source
    if not hasPermission(src) then return end
    BlackoutActive = not BlackoutActive
    TriggerClientEvent('bk_admin:syncBlackout', -1, BlackoutActive)
    logToDiscord("Blackout Toggle", ("Admin **%s** toggled blackout: **%s**"):format(GetPlayerName(src), BlackoutActive and "ON" or "OFF"), "WorldActions")
end)

RegisterNetEvent('bk_admin:setWaves', function(intensity)
    local src = source
    if not hasPermission(src) then return end
    TriggerClientEvent('bk_admin:syncWaves', -1, intensity)
    logToDiscord("Wave Intensity", ("Admin **%s** set waves to **%.1f**"):format(GetPlayerName(src), intensity), "WorldActions")
end)

-- Set Routing Bucket (Dimension)
RegisterNetEvent('bk_admin:setDimension', function(dim)
    local src = source
    if not hasPermission(src) then
        TriggerClientEvent('bk_admin:notify', src, "Keine Berechtigung für Dimensionwechsel")
        return
    end
    local bucket = tonumber(dim) or 0
    SetPlayerRoutingBucket(src, bucket)
    local msg = ("Dimension set to %s"):format(bucket)
    -- Try framework notify if available, otherwise use our NUI notify event as fallback
    clientNotify(src, msg, "success")
    logToDiscord("Dimension Update", ("Admin **%s** changed dimension to **%s**"):format(GetPlayerName(src), bucket), "PlayerActions")
end)

-- Private Message
RegisterNetEvent('bk_admin:privateMessage', function(targetId, title, text)
    local src = source
    if not hasPermission(src) then
        clientNotify(src, "Keine Berechtigung für Privatnachricht", "error")
        return
    end

    local tgt = tonumber(targetId)
    if not tgt then
        clientNotify(src, "Ungültige Ziel-ID für Privatnachricht", "error")
        return
    end

    local safeTitle = title or "Nachricht"
    local safeText = text or ""
    local dur = math.floor((Config.Announcements.Duration or 5.0) * 1000)
    TriggerClientEvent('bk_admin:showAnnouncement', tgt, safeTitle, safeText, dur)
    clientNotify(tgt, ('[PM] %s: %s'):format(safeTitle, safeText), 'primary')
    -- Echo back to sender
    clientNotify(src, "PM gesendet an " .. GetPlayerName(tgt), 'success')
    logToDiscord("Private Message", ("Admin **%s** sent PM to **%s** (ID %s)\n**Title:** %s\n**Message:** %s"):format(GetPlayerName(src), GetPlayerName(tgt), tgt, safeTitle, safeText), "ServerActions")
end)

-- Global Announcement
RegisterNetEvent('bk_admin:announce', function(title, text, duration)
    if not hasPermission(source) then
        clientNotify(source, "Keine Berechtigung für Ankündigung", "error")
        return
    end
    local safeTitle = title or "Ankündigung"
    local safeText = text or ""
    local dur = duration or math.floor((Config.Announcements.Duration or 5.0) * 1000)
    TriggerClientEvent('bk_admin:showAnnouncement', -1, safeTitle, safeText, dur)
    clientNotify(-1, ('[ANN] %s: %s'):format(safeTitle, safeText), 'primary')
    clientNotify(source, "Ankündigung gesendet", 'success')
    logToDiscord("Global Announcement", ("Admin **%s** sent announcement\n**Title:** %s\n**Message:** %s"):format(GetPlayerName(source), safeTitle, safeText), "ServerActions")
end)

-- Offline Ban Command
RegisterCommand("offlineban", function(source, args)
    if source ~= 0 and not hasPermission(source) then return end
    local citizenid = args[1]
    local duration = args[2] -- Days
    local reason = table.concat(args, " ", 3)
    
    if not citizenid or not duration or not reason then
        -- incorrect usage; silently ignore in production
        return
    end

    local expire = 2147483647
    if tonumber(duration) > 0 then expire = os.time() + (tonumber(duration) * 86400) end

    MySQL.insert('INSERT INTO bans (name, license, discord, ip, reason, bannedby, expire) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        "Offline Ban", "N/A", "N/A", "N/A", reason, "System", expire
    }, function(id)
        -- offline ban recorded
    end)
end)

-- Log client-side admin actions
RegisterNetEvent('bk_admin:logAdminAction', function(action, details)
    local src = source
    if not hasPermission(src) then return end
    local category = "AdminActions"
    if action == "NoClip" or action == "Godmode" or action == "Vanish" or action == "ShowIDs" or action == "SuperAdmin" or action == "Visibility" then
        category = "AdminActions"
    elseif action == "Revive Self" or action == "Fix Vehicle" or action == "Teleport Waypoint" or action == "Teleport Coords" or action == "Give All Weapons" or action == "Spawn Object" or action == "Spawn Vehicle" then
        category = "PlayerActions"
    end
    logToDiscord(action, ("Admin **%s** (ID %s): %s"):format(GetPlayerName(src), src, details or ""), category)
end)
