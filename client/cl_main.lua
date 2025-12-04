local presents = {}
local blipsEnabled = false
local isPlacing = false
local placementObj = nil

local function RotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return {
        x = -math.sin(z) * num,
        y = math.cos(z) * num,
        z = math.sin(x)
    }
end

local function RayCastGamePlayCamera(distance)
    local camRot = GetGameplayCamRot(2)
    local camPos = GetGameplayCamCoord()
    local dir = RotationToDirection(camRot)

    local destX = camPos.x + dir.x * distance
    local destY = camPos.y + dir.y * distance
    local destZ = camPos.z + dir.z * distance

    local handle = StartShapeTestRay(
        camPos.x, camPos.y, camPos.z,
        destX, destY, destZ,
        -1, PlayerPedId(), 0
    )

    local _, hit, endCoords, _, _ = GetShapeTestResult(handle)
    return hit == 1, endCoords
end

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('ug_presents:requestPresents')
end)

local function createPresentBlip(id, entity)
    local pos = GetEntityCoords(entity)
    local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
    SetBlipSprite(blip, 842)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, 1)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Present')
    EndTextCommandSetBlipName(blip)

    return blip
end

RegisterNetEvent('ug_presents:spawnPresent', function(id, model, x, y, z, heading)
    id = tonumber(id)
    if not id then return end

    if presents[id] and DoesEntityExist(presents[id].entity) then
        return
    end

    local modelHash = type(model) == 'number' and model or joaat(model)

    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(0)
    end

    local obj = CreateObject(modelHash, x, y, z, false, false, false)

    PlaceObjectOnGroundProperly(obj)
    local groundCoords = GetEntityCoords(obj)
    SetEntityCoords(obj, groundCoords.x, groundCoords.y, groundCoords.z, false, false, false, true)

    SetEntityHeading(obj, heading or 0.0)
    FreezeEntityPosition(obj, true)
    SetEntityAsMissionEntity(obj, true, true)

    exports.ox_target:addLocalEntity(obj, {
        {
            name = 'ug_present_' .. id,
            label = 'Open present',
            icon = 'fa-solid fa-gift',
            onSelect = function(data)
                if Config.OpenPresent and Config.OpenPresent.enabled then
                    local options = {
                        duration = Config.OpenPresent.duration or 5000,
                        label = Config.OpenPresent.label or 'Opening present...',
                        useWhileDead = false,
                        canCancel = true,
                        disable = {
                            move = true,
                            car = true,
                            combat = true,
                        }
                    }

                    if Config.OpenPresent.anim then
                        options.anim = {
                            dict = Config.OpenPresent.anim.dict,
                            clip = Config.OpenPresent.anim.clip,
                            flag = Config.OpenPresent.anim.flag or 49,
                        }
                    end

                    local ok = lib.progressBar(options)

                    if not ok then
                        return
                    end
                end

                TriggerServerEvent('ug_presents:pickupPresent', id)
            end
        }
    })

    local blip
    if blipsEnabled then
        blip = createPresentBlip(id, obj)
    end

    presents[id] = {
        entity = obj,
        blip = blip
    }

    SetModelAsNoLongerNeeded(modelHash)
end)

RegisterNetEvent('ug_presents:removePresent', function(id)
    id = tonumber(id)
    if not id then return end

    local data = presents[id]
    if not data then return end

    if data.blip and DoesBlipExist(data.blip) then
        RemoveBlip(data.blip)
    end

    if data.entity and DoesEntityExist(data.entity) then
        pcall(function()
            exports.ox_target:removeLocalEntity(data.entity)
        end)
        DeleteEntity(data.entity)
    end

    presents[id] = nil
end)

RegisterNetEvent('ug_presents:togglePresentBlips', function()
    blipsEnabled = not blipsEnabled

    if blipsEnabled then
        for id, data in pairs(presents) do
            if data.entity and DoesEntityExist(data.entity) then
                if not data.blip or not DoesBlipExist(data.blip) then
                    data.blip = createPresentBlip(id, data.entity)
                end
            end
        end

        lib.notify({
            type = 'success',
            title = Config.NotifyTitle,
            description = Config.PresentBlipsOnMessage
        })
    else
        for id, data in pairs(presents) do
            if data.blip and DoesBlipExist(data.blip) then
                RemoveBlip(data.blip)
            end
            data.blip = nil
        end

        lib.notify({
            type = 'info',
            title = Config.NotifyTitle,
            description = Config.PresentBlipsOffMessage
        })
    end
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end

    for id, data in pairs(presents) do
        if data.blip and DoesBlipExist(data.blip) then
            RemoveBlip(data.blip)
        end

        if data.entity and DoesEntityExist(data.entity) then
            pcall(function()
                exports.ox_target:removeLocalEntity(data.entity)
            end)
            DeleteEntity(data.entity)
        end
    end
end)

RegisterNetEvent('ug_presents:startPlacement', function(model)
    if isPlacing and placementObj and DoesEntityExist(placementObj) then
        DeleteEntity(placementObj)
        placementObj = nil
    end

    isPlacing = true

    local modelHash = type(model) == 'number' and model or joaat(model)
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(0)
    end

    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)

    placementObj = CreateObject(modelHash, pedCoords.x, pedCoords.y, pedCoords.z, false, false, false)
    SetEntityAlpha(placementObj, 150, false)
    SetEntityCollision(placementObj, false, false)
    SetEntityAsMissionEntity(placementObj, true, true)

    local heading = GetEntityHeading(ped)

    if lib and lib.showTextUI then
        lib.showTextUI('[ENTER/E] Place || [SCROLL] Rotate || [BACKSPACE] Cancel')
    end

    CreateThread(function()
        while isPlacing and placementObj and DoesEntityExist(placementObj) do
            Wait(0)

            local pedNow = PlayerPedId()
            local camHit, hitCoords = RayCastGamePlayCamera(10.0)

            local posX, posY, posZ

            if camHit and hitCoords then
                posX, posY, posZ = hitCoords.x, hitCoords.y, hitCoords.z
            else
                local pc = GetEntityCoords(pedNow)
                local fwd = GetEntityForwardVector(pedNow)
                posX = pc.x + fwd.x * 2.0
                posY = pc.y + fwd.y * 2.0
                posZ = pc.z
            end

            local foundGround, groundZ = GetGroundZFor_3dCoord(posX, posY, posZ + 0.5, false)
            if foundGround then
                posZ = groundZ + 0.02
            end

            SetEntityCoordsNoOffset(placementObj, posX, posY, posZ, false, false, false)
            SetEntityHeading(placementObj, heading)

            if IsControlPressed(0, 96) then
                heading = heading + 1.5
            elseif IsControlPressed(0, 97) then
                heading = heading - 1.5
            end

            if IsControlJustPressed(0, 191) or IsControlJustPressed(0, 38) or IsControlJustPressed(0, 24) or IsControlJustPressed(0, 25) then
                local finalCoords = GetEntityCoords(placementObj)
                local finalHeading = GetEntityHeading(placementObj)

                isPlacing = false

                if lib and lib.hideTextUI then
                    lib.hideTextUI()
                end

                DeleteEntity(placementObj)
                placementObj = nil

                TriggerServerEvent('ug_presents:placePresent', finalCoords.x, finalCoords.y, finalCoords.z, finalHeading)
                break
            end

            if IsControlJustPressed(0, 177) then
                isPlacing = false

                if lib and lib.hideTextUI then
                    lib.hideTextUI()
                end

                DeleteEntity(placementObj)
                placementObj = nil
                break
            end
        end
    end)
end)
