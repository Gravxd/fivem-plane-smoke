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

CreateThread(
    function()
        RequestNamedPtfxAsset(PARTICLE_DICTIONARY)
        while not HasNamedPtfxAssetLoaded(PARTICLE_DICTIONARY) do
            Wait(0)
        end
    end
)

local function Notify(message, type)
    lib.notify({type = type, title = "PlaneSmoke", description = message, position = "center-right"})
end

local SMOKE_DATA = {}
local ShouldDrawSmoke = false

local function StopSmoke(player)
    if not SMOKE_DATA[player] then
        return
    end

    StopParticleFxLooped(SMOKE_DATA[player].handle, false)
    SMOKE_DATA[player] = nil

    if #SMOKE_DATA == 0 then
        ShouldDrawSmoke = false
    end
end

local function GetBoneFromName(VEHICLE, name)
    if name == "Center" then
        return -1
    elseif name == "Right Wing" then
        local RightBone = GetEntityBoneIndexByName(VEHICLE, "wingtip_2")
        return RightBone ~= -1 and RightBone or GetEntityBoneIndexByName(VEHICLE, "aileron_r")
    elseif name == "Left Wing" then
        local LeftBone = GetEntityBoneIndexByName(VEHICLE, "wingtip_1")
        return LeftBone ~= -1 and LeftBone or GetEntityBoneIndexByName(VEHICLE, "aileron_l")
    end
end

local function DrawSmoke()
    CreateThread(
        function()
            while ShouldDrawSmoke do
                for player, data in pairs(SMOKE_DATA) do
                    local PLAYER_ID = GetPlayerFromServerId(player)
                    local PED = GetPlayerPed(PLAYER_ID)
                    local VEHICLE = GetVehiclePedIsIn(PED, false)
                    if DoesEntityExist(VEHICLE) and PED ~= 0 and PLAYER_ID ~= -1 then
                        if data.handle then
                            SetParticleFxLoopedScale(data.handle, data.size + 0.0)
                            SetParticleFxLoopedColour(data.handle, data.r + 0.0, data.g + 0.0, data.b + 0.0, 0)
                        else
                            local BONE = GetBoneFromName(VEHICLE, data.position or "Center")
                            UseParticleFxAssetNextCall(PARTICLE_DICTIONARY)
                            SMOKE_DATA[player].handle =
                                StartNetworkedParticleFxLoopedOnEntityBone(
                                PARTICLE_NAME,
                                VEHICLE,
                                0.0,
                                BONE == -1 and -8.5 or 0.0,
                                0.0,
                                0.0,
                                0.0,
                                0.0,
                                BONE,
                                data.size + 0.0,
                                0.0,
                                0.0,
                                0.0
                            )
                            SetParticleFxLoopedScale(SMOKE_DATA[player].handle, data.size + 0.0)
                            SetParticleFxLoopedColour(
                                SMOKE_DATA[player].handle,
                                data.r + 0.0,
                                data.g + 0.0,
                                data.b + 0.0,
                                0
                            )
                        end
                    end
                end

                Wait(750)
            end
        end
    )
end

local function StartSmoke(player, data)
    if SMOKE_DATA[player] then
        StopSmoke(player)
        SMOKE_DATA[player] = data
    else
        SMOKE_DATA[player] = data
    end

    if not ShouldDrawSmoke then
        ShouldDrawSmoke = true
        DrawSmoke()
    end
end

AddStateBagChangeHandler(
    "vehdata:planesmoke",
    nil,
    function(bagName, _, value)
        local player = GetPlayerFromStateBagName(bagName)
        if player == 0 then
            return
        end

        local player_id = GetPlayerServerId(player)

        if value then
            StartSmoke(player_id, value)
        else
            StopSmoke(player_id)
        end
    end
)

local SmokeSettings =
    GetResourceKvpString("planesmoke_settings") and json.decode(GetResourceKvpString("planesmoke_settings")) or
    DefaultSmokeSettings

local function HexToRGB(hex)
    hex = hex:gsub("#", "")
    return tonumber("0x" .. hex:sub(1, 2)) / 255, tonumber("0x" .. hex:sub(3, 4)) / 255, tonumber("0x" .. hex:sub(5, 6)) /
        255
end

local SmokeEnabled = false

lib.onCache(
    "vehicle",
    function(value)
        if SmokeEnabled then
            SmokeEnabled = false
            LocalPlayer.state:set("vehdata:planesmoke", nil, true)
        end
    end
)

RegisterCommand(
    "smoke",
    function()
        if SmokeEnabled then
            -- disable
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

        CreateThread(
            function()
                while SmokeEnabled do
                    if not GetIsVehicleEngineRunning(cache.vehicle) or IsEntityDead(cache.vehicle) then
                        LocalPlayer.state:set("vehdata:planesmoke", nil, true)
                        SmokeEnabled = false
                        break
                    end
                    Wait(2000)
                end
            end
        )
    end,
    false
)

local PositionOptions = {}
local Positions = {"Left Wing", "Right Wing", "Center"}
for i = 1, #Positions do
    PositionOptions[#PositionOptions + 1] = {label = Positions[i], value = Positions[i]}
end
RegisterCommand(
    "smokeconfig",
    function()
        local Input =
            lib.inputDialog(
            "Smoke Settings",
            {
                {type = "slider", label = "Size", default = SmokeSettings.size, min = 0.1, max = 2.0, step = 0.05},
                {type = "color", label = "Colour", default = SmokeSettings.hex},
                {
                    type = "select",
                    label = "Position",
                    options = PositionOptions,
                    default = SmokeSettings.position,
                    required = true
                },
                {type = "checkbox", label = "Reset To Default", checked = false}
            }
        )

        if not Input then
            return
        end

        if Input[4] then
            SmokeSettings = DefaultSmokeSettings
            Notify("Smoke settings have been reset to default!", "success")

            if SmokeEnabled then
                LocalPlayer.state:set("vehdata:planesmoke", SmokeSettings, true)
            end
        else
            local r, g, b = HexToRGB(Input[2])
            local New = {size = Input[1], hex = Input[2], position = Input[3], r = r, g = g, b = b}
            SmokeSettings = New

            Notify("Smoke settings have been updated!", "success")
            if SmokeEnabled then
                LocalPlayer.state:set("vehdata:planesmoke", SmokeSettings, true)
            end
        end
        SetResourceKvp("planesmoke_settings", json.encode(SmokeSettings))
    end,
    false
)

RegisterKeyMapping("smoke", "Toggle PlaneSmoke", "keyboard", "")
TriggerEvent("chat:addSuggestion", "/smoke", "Toggle Plane Smoke!")
TriggerEvent("chat:addSuggestion", "/smokeconfig", "Customise your plane smoke!")
