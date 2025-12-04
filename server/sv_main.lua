local ESX, QBCore, QBOX
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
    elseif Config.Framework == 'qb' then
        if GetResourceState('qb-core') == 'started' then
            QBCore = exports['qb-core']:GetCoreObject()
            print('[ug_presents] QB-Core framework detected.')
        else
            print('^1[ug_presents] Config.Framework = "qb" but qb-core is not started!^0')
        end
    elseif Config.Framework == 'qbox' then
        if GetResourceState('qbx_core') == 'started' then
            QBOX = exports['qbx_core']:GetCoreObject()
            print('[ug_presents] QBOX framework detected.')
        else
            print('^1[ug_presents] Config.Framework = "qbox" but qbx_core is not started!^0')
        end
    else
        print('^1[ug_presents] Invalid Config.Framework, use "esx", "qb" or "qbox".^0')
    end
end)

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
    elseif Config.Framework == 'qb' and QBCore then
        for _, perm in ipairs(Config.QBPermissions or {}) do
            if QBCore.Functions.HasPermission(src, perm) then
                return true
            end
        end
    elseif Config.Framework == 'qbox' and QBOX then
        local perms = Config.QBOXPermissions or Config.QBPermissions or {}
        for _, perm in ipairs(perms) do
            if QBOX.Functions.HasPermission(src, perm) then
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
end, false)

RegisterNetEvent('ug_presents:placePresent', function(x, y, z, heading)
    local src = source

    if not CanManagePresents(src) then
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
        return
    end

    local src = source
    local ped = GetPlayerPed(src)
    if not DoesEntityExist(ped) then return end

    local coords = GetEntityCoords(ped)
    local closestId, closestDist

    for id, p in pairs(activePresents) do
        local dx = coords.x - p.x
        local dy = coords.y - p.y
        local dz = coords.z - p.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if not closestDist or dist < closestDist then
            closestDist = dist
            closestId = id
        end
    end

    local maxDist = Config.DeleteDistance or 5.0
    if not closestId or not closestDist or closestDist > maxDist then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            title = Config.NotifyTitle,
            description = Config.NoPresentNearbyMessage
        })
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
        return
    end

    TriggerClientEvent('ug_presents:togglePresentBlips', source)
end, false)

RegisterCommand('presentcleanexpired', function(source, args, _)
    if source ~= 0 and not CanManagePresents(source) then
        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                type = 'error',
                title = Config.NotifyTitle,
                description = Config.NoPermissionMessage
            })
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
            else
                print('[ug_presents] No expired presents to clean.')
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
        else
            print(('[ug_presents] Cleaned %d expired presents.'):format(count))
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
        end
        return
    end

    local src = source ~= 0 and source or nil

    MySQL.update('DELETE FROM ug_presents', {})

    for id, _ in pairs(activePresents) do
        TriggerClientEvent('ug_presents:removePresent', -1, id)
    end
    activePresents = {}

    if src then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'success',
            title = Config.NotifyTitle,
            description = 'All presents have been cleaned up.'
        })
    else
        print('[ug_presents] All presents have been cleaned up.')
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
        return
    end

    local reward = Config.Rewards[math.random(1, #Config.Rewards)]
    if not reward or not reward.item then
        processingPresents[presentId] = nil
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

    processingPresents[presentId] = nil
end)
