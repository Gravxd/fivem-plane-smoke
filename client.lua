local PARTICLE_DICTIONARY = "scr_ar_planes"
local PARTICLE_NAME = "scr_ar_trail_smoke"

local DefaultSmokeSettings = {
    size = 0.6,
    r = 255 / 255,
    g = 250 / 255,
    b = 255 / 255,
    hex = "#fffaff",
    position = "Center"
}

CreateThread(function()
    RequestNamedPtfxAsset(PARTICLE_DICTIONARY)
    while not HasNamedPtfxAssetLoaded(PARTICLE_DICTIONARY) do
        Wait(0)
    end
end)

local function Notify(message, type)
    lib.notify({type = type, title = "PlaneSmoke", description = message, position = "center-right"})
end

local SMOKE_DATA = {}
local ShouldDrawSmoke = false

local function StopSmoke(player)
    local smokeData = SMOKE_DATA[player]
    if not smokeData then return end

    StopParticleFxLooped(smokeData.handle, false)
    SMOKE_DATA[player] = nil

    if next(SMOKE_DATA) == nil then
        ShouldDrawSmoke = false
    end
end

local function GetBoneFromName(vehicle, name)
    if name == "Center" then
        return -1
    elseif name == "Right Wing" then
        return GetEntityBoneIndexByName(vehicle, "wingtip_2") or GetEntityBoneIndexByName(vehicle, "aileron_r")
    elseif name == "Left Wing" then
        return GetEntityBoneIndexByName(vehicle, "wingtip_1") or GetEntityBoneIndexByName(vehicle, "aileron_l")
    end
end

local function DrawSmoke()
    CreateThread(function()
        while ShouldDrawSmoke do
            for player, data in pairs(SMOKE_DATA) do
                local playerId = GetPlayerFromServerId(player)
                local ped = GetPlayerPed(playerId)
                local vehicle = GetVehiclePedIsIn(ped, false)
                if DoesEntityExist(vehicle) and ped ~= 0 and playerId ~= -1 then
                    if data.handle then
                        SetParticleFxLoopedScale(data.handle, data.size)
                        SetParticleFxLoopedColour(data.handle, data.r, data.g, data.b, 0)
                    else
                        local bone = GetBoneFromName(vehicle, data.position or "Center")
                        UseParticleFxAssetNextCall(PARTICLE_DICTIONARY)
                        data.handle = StartNetworkedParticleFxLoopedOnEntityBone(
                            PARTICLE_NAME, vehicle, 0.0, bone == -1 and -8.5 or 0.0, 0.0, 0.0, 0.0, 0.0, bone, data.size, 0.0, 0.0, 0.0
                        )
                        SetParticleFxLoopedScale(data.handle, data.size)
                        SetParticleFxLoopedColour(data.handle, data.r, data.g, data.b, 0)
                    end
                end
            end
            Wait(750)
        end
    end)
end

local function StartSmoke(player, data)
    StopSmoke(player)
    SMOKE_DATA[player] = data

    if not ShouldDrawSmoke then
        ShouldDrawSmoke = true
        DrawSmoke()
    end
end

AddStateBagChangeHandler("vehdata:planesmoke", nil, function(bagName, _, value)
    local player = GetPlayerFromStateBagName(bagName)
    if player == 0 then return end

    local playerId = GetPlayerServerId(player)
    if value then
        StartSmoke(playerId, value)
    else
        StopSmoke(playerId)
    end
end)

local SmokeSettings = GetResourceKvpString("planesmoke_settings") and json.decode(GetResourceKvpString("planesmoke_settings")) or DefaultSmokeSettings

local function HexToRGB(hex)
    hex = hex:gsub("#", "")
    return tonumber("0x" .. hex:sub(1, 2)) / 255, tonumber("0x" .. hex:sub(3, 4)) / 255, tonumber("0x" .. hex:sub(5, 6)) / 255
end

local SmokeEnabled = false

lib.onCache("vehicle", function(value)
    if SmokeEnabled then
        SmokeEnabled = false
        LocalPlayer.state:set("vehdata:planesmoke", nil, true)
    end
end)

RegisterCommand("smoke", function()
    if SmokeEnabled then
        SmokeEnabled = false
        LocalPlayer.state:set("vehdata:planesmoke", nil, true)
        return
    end

    if not IsPedInAnyPlane(cache.ped) then
        return Notify("You must be in an aircraft to enable smoke!", "error")
    end
    if cache.seat ~= -1 then
        return Notify("You must be the pilot to enable smoke!", "error")
    end

    SmokeEnabled = true
    LocalPlayer.state:set("vehdata:planesmoke", SmokeSettings, true)

    CreateThread(function()
        while SmokeEnabled do
            if not GetIsVehicleEngineRunning(cache.vehicle) or IsEntityDead(cache.vehicle) then
                LocalPlayer.state:set("vehdata:planesmoke", nil, true)
                SmokeEnabled = false
                break
            end
            Wait(2000)
        end
    end)
end, false)

local PositionOptions = {}
local Positions = {"Left Wing", "Right Wing", "Center"}
for i = 1, #Positions do
    PositionOptions[#PositionOptions + 1] = {label = Positions[i], value = Positions[i]}
end

RegisterCommand("smokeconfig", function()
    local Input = lib.inputDialog("Smoke Settings", {
        {type = "slider", label = "Size", default = SmokeSettings.size, min = 0.1, max = 2.0, step = 0.05},
        {type = "color", label = "Colour", default = SmokeSettings.hex},
        {type = "select", label = "Position", options = PositionOptions, default = SmokeSettings.position, required = true},
        {type = "checkbox", label = "Reset To Default", checked = false}
    })

    if not Input then return end

    if Input[4] then
        SmokeSettings = DefaultSmokeSettings
        Notify("Smoke settings have been reset to default!", "success")
    else
        local r, g, b = HexToRGB(Input[2])
        SmokeSettings = {size = Input[1], hex = Input[2], position = Input[3], r = r, g = g, b = b}
        Notify("Smoke settings have been updated!", "success")
    end

    if SmokeEnabled then
        LocalPlayer.state:set("vehdata:planesmoke", SmokeSettings, true)
    end
    SetResourceKvp("planesmoke_settings", json.encode(SmokeSettings))
end, false)

RegisterKeyMapping("smoke", "Toggle PlaneSmoke", "keyboard", "")
TriggerEvent("chat:addSuggestion", "/smoke", "Toggle Plane Smoke!")
TriggerEvent("chat:addSuggestion", "/smokeconfig", "Customise your plane smoke!")