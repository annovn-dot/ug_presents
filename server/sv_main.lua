local ESX, QBCore
local activePresents = {}
local processingPresents = {}
local pendingPlacement = {}

CreateThread(function()
    if Config.Framework == 'esx' then
        if GetResourceState('es_extended') == 'started' then
            ESX = exports['es_extended']:getSharedObject()
            print('[ug_presents] ESX framework detected.')
        else
            print('^1[ug_presents] Config.Framework = "esx" but es_extended is not started!^0')
        end
    elseif Config.Framework == 'qb' or Config.Framework == 'qbox' then
        if GetResourceState('qb-core') == 'started' then
            QBCore = exports['qb-core']:GetCoreObject()
            print('[ug_presents] QB-Core / QBOX (qb-core bridge) detected.')
        else
            print(('^1[ug_presents] Config.Framework = "%s" but qb-core is not started!^0'):format(Config.Framework))
        end
    else
        print('^1[ug_presents] Invalid Config.Framework, use "esx", "qb" or "qbox".^0')
    end
end)

local function GetPlayerInfo(src)
    local name = GetPlayerName(src) or 'Unknown'
    local identifier = 'unknown'
    local cid = 'unknown'

    if Config.Framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            identifier = xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier or identifier
            name = xPlayer.getName and xPlayer.getName() or name
        end
    elseif (Config.Framework == 'qb' or Config.Framework == 'qbox') and QBCore then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player and Player.PlayerData then
            cid = Player.PlayerData.citizenid or cid
            identifier = Player.PlayerData.license or Player.PlayerData.steam or cid or identifier

            local charinfo = Player.PlayerData.charinfo
            if charinfo and charinfo.firstname and charinfo.lastname then
                name = (charinfo.firstname .. ' ' .. charinfo.lastname)
            end
        end
    end

    return name, identifier, cid
end

local function SendPresentLog(title, description, color, fields, footer)
    local webhook = Config.PresentsWebhook or Config.DiscordWebhook
    if not webhook or webhook == '' then return end

    local embed = {
        title = title,
        description = description,
        color = color or 0x2f3136,
        footer = { text = footer or os.date('%Y-%m-%d %H:%M:%S') },
        fields = fields,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }

    PerformHttpRequest(webhook, function() end, 'POST', json.encode({
        username = Config.PresentsLogUsername or 'ug_presents',
        embeds = { embed }
    }), {
        ['Content-Type'] = 'application/json'
    })
end

local function CanManagePresents(src)
    if Config.Framework == 'esx' and ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end

        local group = xPlayer.getGroup and xPlayer.getGroup() or 'user'
        for _, allowed in ipairs(Config.ESXGroups or {}) do
            if group == allowed then
                return true
            end
        end
    elseif (Config.Framework == 'qb' or Config.Framework == 'qbox') and QBCore then
        local perms = Config.QBOXPermissions
        if Config.Framework == 'qb' then
            perms = Config.QBPermissions
        end
        perms = perms or Config.QBPermissions or { 'admin', 'god' }

        for _, perm in ipairs(perms) do
            if QBCore.Functions.HasPermission(src, perm) then
                return true
            end
        end
    end

    return false
end

local function getRandomPropModel()
    if not Config.Props or #Config.Props == 0 then return nil end
    return Config.Props[math.random(1, #Config.Props)]
end

AddEventHandler('playerDropped', function()
    local src = source
    pendingPlacement[src] = nil
end)

MySQL.ready(function()
    MySQL.query('SELECT * FROM ug_presents', {}, function(rows)
        if not rows or #rows == 0 then
            print('[ug_presents] No presents to load from database.')
            SendPresentLog('Presents Init', 'No presents to load from database on resource start.', 0x95a5a6)
            return
        end

        local now = os.time()
        local loaded = 0
        local expiredCount = 0

        for _, row in ipairs(rows) do
            local expiresAt = row.expires_at
            if expiresAt and expiresAt > 0 and expiresAt <= now then
                expiredCount = expiredCount + 1
                MySQL.update('DELETE FROM ug_presents WHERE id = ?', { row.id })
            else
                activePresents[row.id] = {
                    id = row.id,
                    model = row.model,
                    x = row.x,
                    y = row.y,
                    z = row.z,
                    heading = row.heading,
                    expires_at = expiresAt
                }
                loaded = loaded + 1
            end
        end

        print(('[ug_presents] Loaded %d presents (cleaned %d expired on start)'):format(loaded, expiredCount))

        SendPresentLog(
            'Presents Init',
            ('Resource started.\nLoaded **%d** presents.\nCleaned **%d** expired presents.'):format(loaded, expiredCount),
            0x3498db,
            {
                { name = 'Loaded',          value = tostring(loaded),       inline = true },
                { name = 'Expired Cleaned', value = tostring(expiredCount), inline = true },
                { name = 'Total in DB',     value = tostring(#rows),        inline = true }
            }
        )

        for _, playerId in ipairs(GetPlayers()) do
            local src = tonumber(playerId)
            for id, p in pairs(activePresents) do
                TriggerClientEvent('ug_presents:spawnPresent', src, id, p.model, p.x, p.y, p.z, p.heading)
            end
        end
    end)
end)

RegisterNetEvent('ug_presents:requestPresents', function()
    local src = source
    for id, p in pairs(activePresents) do
        TriggerClientEvent('ug_presents:spawnPresent', src, id, p.model, p.x, p.y, p.z, p.heading)
    end
end)

RegisterCommand('presentcreate', function(source, args, _)
    if source == 0 then
        print('[ug_presents] Use this command in-game.')
        return
    end

    if not CanManagePresents(source) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            title = Config.NotifyTitle,
            description = Config.NoPermissionMessage
        })

        local name, identifier, cid = GetPlayerInfo(source)
        SendPresentLog(
            'Present Create - No Permission',
            ('%s (%s) tried to use `/presentcreate` without permission.'):format(name, identifier),
            0xe74c3c
        )

        return
    end

    local src = source
    local arg1 = args[1]
    local arg2 = args[2]

    local modelName
    local expiryHours

    if not arg1 then
        modelName = getRandomPropModel()
        if not modelName then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = Config.NotifyTitle,
                description = 'No props configured.'
            })
            return
        end
    else
        local lower = string.lower(arg1)

        if lower == 'r' or lower == 'random' then
            modelName = getRandomPropModel()
            if not modelName then
                TriggerClientEvent('ox_lib:notify', src, {
                    type = 'error',
                    title = Config.NotifyTitle,
                    description = 'No props configured.'
                })
                return
            end
            if arg2 then
                expiryHours = tonumber(arg2)
            end
        else
            if arg2 then
                local index = tonumber(arg1)
                if index and Config.Props[index] then
                    modelName = Config.Props[index]
                else
                    modelName = arg1
                end
                expiryHours = tonumber(arg2)
            else
                local index = tonumber(arg1)
                if index and Config.Props[index] then
                    modelName = Config.Props[index]
                else
                    modelName = arg1
                end
            end
        end
    end

    if expiryHours and expiryHours <= 0 then
        expiryHours = nil
    end

    pendingPlacement[src] = {
        model = modelName,
        expiresIn = expiryHours
    }

    TriggerClientEvent('ug_presents:startPlacement', src, modelName)

    TriggerClientEvent('ox_lib:notify', src, {
        type = 'info',
        title = Config.NotifyTitle,
        description = 'Placement mode: [Enter/E] place, [←/→] rotate, [Backspace] cancel.'
    })

    local name, identifier, cid = GetPlayerInfo(src)
    SendPresentLog(
        'Present Placement Started',
        ('%s (%s) started placement for model `%s`.'):format(name, identifier, modelName),
        0x1abc9c,
        {
            { name = 'Expiry (hours)', value = expiryHours and tostring(expiryHours) or 'None', inline = true }
        }
    )
end, false)

RegisterNetEvent('ug_presents:placePresent', function(x, y, z, heading)
    local src = source

    if not CanManagePresents(src) then
        local name, identifier = GetPlayerInfo(src)
        SendPresentLog(
            'Present Place - No Permission',
            ('%s (%s) tried to place a present without permission.'):format(name, identifier),
            0xe74c3c
        )
        return
    end

    local info = pendingPlacement[src]
    if not info or not info.model then
        return
    end

    pendingPlacement[src] = nil

    x = tonumber(x)
    y = tonumber(y)
    z = tonumber(z)
    heading = tonumber(heading) or 0.0

    if not x or not y or not z then
        return
    end

    local modelName = info.model
    local expiryHours = info.expiresIn
    local expiresAt = nil

    if expiryHours and expiryHours > 0 then
        expiresAt = os.time() + math.floor(expiryHours * 3600)
    end

    MySQL.insert('INSERT INTO ug_presents (model, x, y, z, heading, expires_at) VALUES (?, ?, ?, ?, ?, ?)', {
        modelName, x, y, z, heading, expiresAt
    }, function(insertId)
        if not insertId then
            print('[ug_presents] Failed to insert present into DB (placement)')

            local name, identifier = GetPlayerInfo(src)
            SendPresentLog(
                'Present Place - DB Error',
                ('%s (%s) tried to place model `%s` but DB insert failed.'):format(name, identifier, modelName),
                0xe74c3c
            )
            return
        end

        activePresents[insertId] = {
            id = insertId,
            model = modelName,
            x = x,
            y = y,
            z = z,
            heading = heading,
            expires_at = expiresAt
        }

        TriggerClientEvent('ug_presents:spawnPresent', -1, insertId, modelName, x, y, z, heading)

        TriggerClientEvent('ox_lib:notify', src, {
            type = 'success',
            title = Config.NotifyTitle,
            description = ('Present placed (model %s, ID: %d%s)'):format(
                modelName,
                insertId,
                expiresAt and (', expires in ~' .. expiryHours .. 'h') or ''
            )
        })

        local name, identifier, cid = GetPlayerInfo(src)
        local fields = {
            { name = 'Present ID', value = tostring(insertId),                                          inline = true },
            { name = 'Model',      value = tostring(modelName),                                         inline = true },
            { name = 'Coords',     value = ('x=%.2f, y=%.2f, z=%.2f, h=%.2f'):format(x, y, z, heading), inline = false }
        }
        if expiryHours then
            fields[#fields + 1] = { name = 'Expires In', value = tostring(expiryHours) .. 'h', inline = true }
        end

        SendPresentLog(
            'Present Placed',
            ('%s (%s) placed a present.'):format(name, identifier),
            0x2ecc71,
            fields
        )
    end)
end)

RegisterCommand('presentdelete', function(source, args, _)
    if source == 0 then
        print('[ug_presents] Use this command in-game.')
        return
    end

    if not CanManagePresents(source) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            title = Config.NotifyTitle,
            description = Config.NoPermissionMessage
        })

        local name, identifier = GetPlayerInfo(source)
        SendPresentLog(
            'Present Delete - No Permission',
            ('%s (%s) tried to use `/presentdelete` without permission.'):format(name, identifier),
            0xe74c3c
        )
        return
    end

    local src = source
    local ped = GetPlayerPed(src)
    if not DoesEntityExist(ped) then return end

    local coords = GetEntityCoords(ped)
    local closestId, closestDist
    local closestData

    for id, p in pairs(activePresents) do
        local dx = coords.x - p.x
        local dy = coords.y - p.y
        local dz = coords.z - p.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if not closestDist or dist < closestDist then
            closestDist = dist
            closestId = id
            closestData = p
        end
    end

    local maxDist = Config.DeleteDistance or 5.0
    if not closestId or not closestDist or closestDist > maxDist then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.NotifyTitle,
            description = Config.NoPresentNearbyMessage
        })

        local name, identifier = GetPlayerInfo(src)
        SendPresentLog(
            'Present Delete - None Nearby',
            ('%s (%s) used `/presentdelete` but no present was within %.1fm.'):format(name, identifier, maxDist),
            0xf1c40f
        )
        return
    end

    activePresents[closestId] = nil
    MySQL.update('DELETE FROM ug_presents WHERE id = ?', { closestId })
    TriggerClientEvent('ug_presents:removePresent', -1, closestId)

    TriggerClientEvent('ox_lib:notify', src, {
        type = 'success',
        title = Config.NotifyTitle,
        description = Config.PresentDeletedMessage:format(closestId)
    })

    local name, identifier = GetPlayerInfo(src)
    local fields
    if closestData then
        fields = {
            { name = 'Present ID', value = tostring(closestId),                                                            inline = true },
            { name = 'Model',      value = tostring(closestData.model),                                                    inline = true },
            { name = 'Coords',     value = ('x=%.2f, y=%.2f, z=%.2f'):format(closestData.x, closestData.y, closestData.z), inline = false },
            { name = 'Distance',   value = ('%.2fm'):format(closestDist),                                                  inline = true }
        }
    else
        fields = {
            { name = 'Present ID', value = tostring(closestId),           inline = true },
            { name = 'Distance',   value = ('%.2fm'):format(closestDist), inline = true }
        }
    end

    SendPresentLog(
        'Present Deleted',
        ('%s (%s) deleted a present.'):format(name, identifier),
        0xe67e22,
        fields
    )
end, false)

RegisterCommand('presentlocate', function(source, args, _)
    if source == 0 then
        print('[ug_presents] Use this command in-game.')
        return
    end

    if not CanManagePresents(source) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            title = Config.NotifyTitle,
            description = Config.NoPermissionMessage
        })

        local name, identifier = GetPlayerInfo(source)
        SendPresentLog(
            'Present Locate - No Permission',
            ('%s (%s) tried to use `/presentlocate` without permission.'):format(name, identifier),
            0xe74c3c
        )
        return
    end

    TriggerClientEvent('ug_presents:togglePresentBlips', source)

    local name, identifier = GetPlayerInfo(source)
    SendPresentLog(
        'Present Locate Toggled',
        ('%s (%s) toggled present blips with `/presentlocate`.'):format(name, identifier),
        0x9b59b6
    )
end, false)

RegisterCommand('presentcleanexpired', function(source, args, _)
    if source ~= 0 and not CanManagePresents(source) then
        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'error',
                title = Config.NotifyTitle,
                description = Config.NoPermissionMessage
            })

            local name, identifier = GetPlayerInfo(source)
            SendPresentLog(
                'Present CleanExpired - No Permission',
                ('%s (%s) tried to use `/presentcleanexpired` without permission.'):format(name, identifier),
                0xe74c3c
            )
        end
        return
    end

    local src = source ~= 0 and source or nil
    local now = os.time()

    MySQL.query('SELECT id FROM ug_presents WHERE expires_at IS NOT NULL AND expires_at <= ?', { now }, function(rows)
        if not rows or #rows == 0 then
            if src then
                TriggerClientEvent('ox_lib:notify', src, {
                    type = 'info',
                    title = Config.NotifyTitle,
                    description = 'No expired presents to clean.'
                })

                local name, identifier = GetPlayerInfo(src)
                SendPresentLog(
                    'Present CleanExpired - None',
                    ('%s (%s) ran `/presentcleanexpired` but there were no expired presents.'):format(name, identifier),
                    0xf1c40f
                )
            else
                print('[ug_presents] No expired presents to clean.')
                SendPresentLog(
                    'Present CleanExpired - None',
                    'Console ran `/presentcleanexpired` but there were no expired presents.',
                    0xf1c40f
                )
            end
            return
        end

        local count = #rows

        MySQL.update('DELETE FROM ug_presents WHERE expires_at IS NOT NULL AND expires_at <= ?', { now })

        for _, row in ipairs(rows) do
            local id = row.id
            activePresents[id] = nil
            TriggerClientEvent('ug_presents:removePresent', -1, id)
        end

        if src then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'success',
                title = Config.NotifyTitle,
                description = ('Cleaned %d expired presents.'):format(count)
            })

            local name, identifier = GetPlayerInfo(src)
            SendPresentLog(
                'Present CleanExpired',
                ('%s (%s) cleaned **%d** expired presents.'):format(name, identifier, count),
                0x2ecc71,
                {
                    { name = 'Count', value = tostring(count), inline = true }
                }
            )
        else
            print(('[ug_presents] Cleaned %d expired presents.'):format(count))
            SendPresentLog(
                'Present CleanExpired',
                ('Console cleaned **%d** expired presents.'):format(count),
                0x2ecc71,
                {
                    { name = 'Count', value = tostring(count), inline = true }
                }
            )
        end
    end)
end, false)

RegisterCommand('presentcleanup', function(source, args, _)
    if source ~= 0 and not CanManagePresents(source) then
        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'error',
                title = Config.NotifyTitle,
                description = Config.NoPermissionMessage
            })

            local name, identifier = GetPlayerInfo(source)
            SendPresentLog(
                'Present Cleanup - No Permission',
                ('%s (%s) tried to use `/presentcleanup` without permission.'):format(name, identifier),
                0xe74c3c
            )
        end
        return
    end

    local src = source ~= 0 and source or nil

    MySQL.update('DELETE FROM ug_presents', {})

    local removedCount = 0
    for id, _ in pairs(activePresents) do
        TriggerClientEvent('ug_presents:removePresent', -1, id)
        removedCount = removedCount + 1
    end
    activePresents = {}

    if src then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'success',
            title = Config.NotifyTitle,
            description = 'All presents have been cleaned up.'
        })

        local name, identifier = GetPlayerInfo(src)
        SendPresentLog(
            'Present Cleanup',
            ('%s (%s) cleaned up ALL presents.'):format(name, identifier),
            0xe74c3c,
            {
                { name = 'Removed Count', value = tostring(removedCount), inline = true }
            }
        )
    else
        print('[ug_presents] All presents have been cleaned up.')
        SendPresentLog(
            'Present Cleanup',
            ('Console cleaned up ALL presents (removed %d).'):format(removedCount),
            0xe74c3c,
            {
                { name = 'Removed Count', value = tostring(removedCount), inline = true }
            }
        )
    end
end, false)

RegisterNetEvent('ug_presents:pickupPresent', function(presentId)
    local src = source
    presentId = tonumber(presentId)
    if not presentId then return end

    if not Config.Rewards or #Config.Rewards == 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.NotifyTitle,
            description = Config.NoRewardsMessage
        })

        local name, identifier = GetPlayerInfo(src)
        SendPresentLog(
            'Present Pickup - No Rewards Configured',
            ('%s (%s) tried to pick up present ID %s but no rewards are configured.'):format(name, identifier,
                tostring(presentId)),
            0xe74c3c
        )
        return
    end

    if processingPresents[presentId] then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.NotifyTitle,
            description = Config.ProcessingMessage
        })
        return
    end
    processingPresents[presentId] = true

    local present = activePresents[presentId]
    if not present then
        processingPresents[presentId] = nil
        TriggerClientEvent('ug_presents:removePresent', src, presentId)
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.NotifyTitle,
            description = Config.PresentTakenMessage
        })

        local name, identifier = GetPlayerInfo(src)
        SendPresentLog(
            'Present Pickup - Already Taken',
            ('%s (%s) tried to pick up present ID %s but it was already gone.'):format(name, identifier,
                tostring(presentId)),
            0xf1c40f
        )
        return
    end

    local now = os.time()
    local exp = present.expires_at
    if exp and exp > 0 and exp <= now then
        processingPresents[presentId] = nil
        activePresents[presentId] = nil
        MySQL.update('DELETE FROM ug_presents WHERE id = ?', { presentId })
        TriggerClientEvent('ug_presents:removePresent', -1, presentId)
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.NotifyTitle,
            description = Config.PresentExpiredMessage or 'This present has expired.'
        })

        local name, identifier = GetPlayerInfo(src)
        SendPresentLog(
            'Present Pickup - Expired',
            ('%s (%s) tried to pick up present ID %s but it was expired and has been deleted.'):format(name, identifier,
                tostring(presentId)),
            0xf1c40f,
            {
                { name = 'Present ID', value = tostring(presentId),     inline = true },
                { name = 'Model',      value = tostring(present.model), inline = true }
            }
        )
        return
    end

    local reward = Config.Rewards[math.random(1, #Config.Rewards)]
    if not reward or not reward.item then
        processingPresents[presentId] = nil

        local name, identifier = GetPlayerInfo(src)
        SendPresentLog(
            'Present Pickup - Invalid Reward',
            ('%s (%s) picked up present ID %s but selected reward entry was invalid.'):format(name, identifier,
                tostring(presentId)),
            0xe74c3c
        )
        return
    end

    local amount = math.random(reward.min or 1, reward.max or 1)

    local ok = exports.ox_inventory:AddItem(src, reward.item, amount)
    if not ok then
        processingPresents[presentId] = nil

        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.NotifyTitle,
            description = Config.InventoryFullMessage
        })

        local name, identifier = GetPlayerInfo(src)
        SendPresentLog(
            'Present Pickup - Inventory Full',
            ('%s (%s) tried to receive reward `%s` x%d from present ID %s but inventory was full.'):format(
                name, identifier, reward.item, amount, tostring(presentId)
            ),
            0xe67e22,
            {
                { name = 'Present ID',  value = tostring(presentId),   inline = true },
                { name = 'Reward Item', value = tostring(reward.item), inline = true },
                { name = 'Amount',      value = tostring(amount),      inline = true }
            }
        )
        return
    end

    activePresents[presentId] = nil
    MySQL.update('DELETE FROM ug_presents WHERE id = ?', { presentId })
    TriggerClientEvent('ug_presents:removePresent', -1, presentId)

    local items = exports.ox_inventory:Items()
    local itemData = items and items[reward.item] or nil
    local label = itemData and itemData.label or reward.item

    TriggerClientEvent('ox_lib:notify', src, {
        type = 'success',
        title = Config.NotifyTitle,
        description = Config.ReceivedMessage:format(amount, label)
    })

    local name, identifier = GetPlayerInfo(src)
    local fields = {
        { name = 'Present ID',  value = tostring(presentId),     inline = true },
        { name = 'Model',       value = tostring(present.model), inline = true },
        { name = 'Reward Item', value = tostring(reward.item),   inline = true },
        { name = 'Amount',      value = tostring(amount),        inline = true }
    }

    if present.x and present.y and present.z then
        fields[#fields + 1] = {
            name = 'Present Coords',
            value = ('x=%.2f, y=%.2f, z=%.2f'):format(present.x, present.y, present.z),
            inline = false
        }
    end

    SendPresentLog(
        'Present Picked Up',
        ('%s (%s) picked up a present and received `%s` x%d.'):format(name, identifier, reward.item, amount),
        0x2ecc71,
        fields
    )

    processingPresents[presentId] = nil
end)
