-- =========================================================
-- SMALL PLANE COCKPIT - CC:SABLE VERSION
--
-- Requires:
--   CC:Sable
--   Advanced Monitor
--   Speaker
--   Redstone Link for throttle
--   Downward Optical Sensor
--
-- Flight sensors are NOT required.
-- =========================================================

local dfpwm = require("cc.audio.dfpwm")


-- =========================================================
-- AIRPORT DATABASE
-- =========================================================
--
-- x / z:
--     Approximate centre of airport/runway.
--
-- elevation:
--     ALT value which should count as AGL 0 at this airport.
--     Easiest way:
--       Park plane on runway and look at displayed ALT.
--
-- radius:
--     Inside this horizontal radius:
--       - airport AGL is enabled
--       - landing callouts are enabled
--       - optical TERRAIN warning is disabled
--
-- Add as many airports as you want.
-- =========================================================

local AIRPORTS = {

    TEST = {
        x = -676,
        z = -1316,
        elevation = -56,
        radius = 200
    },

    -- Example:
    --
    -- HOME = {
    --     x = 100,
    --     z = -300,
    --     elevation = 63,
    --     radius = 200
    -- },
    --
    -- THEMEPARK = {
    --     x = -900,
    --     z = 450,
    --     elevation = 64,
    --     radius = 200
    -- }

}


-- =========================================================
-- SABLE ORIENTATION SETTINGS
-- =========================================================
--
-- Your tests strongly suggest:
--
-- Euler 1 = bank / roll
-- Euler 2 = yaw
-- Euler 3 = pitch
--
-- If something is wrong, these are easy to change.
-- =========================================================

local BANK_EULER_AXIS = 1
local PITCH_EULER_AXIS = 3

local BANK_SIGN = 1
local PITCH_SIGN = 1

-- If level flight does not show approximately 0:
--
-- Example:
-- display says BANK +3 while perfectly level
-- set BANK_ZERO_DEG = 3
--
local BANK_ZERO_DEG = 0
local PITCH_ZERO_DEG = 0


-- =========================================================
-- DISPLAY SETTINGS
-- =========================================================

local PITCH_DEGREES_PER_ROW = 10


-- =========================================================
-- THROTTLE
-- =========================================================
--
-- nil = automatically find strongest redstone input from
--       a side which is NOT occupied by a CC peripheral.
--
-- You can instead force:
-- "left", "right", "top", "bottom", "front", "back"
-- =========================================================

local THRUST_SIDE = nil


-- =========================================================
-- BANK WARNING
-- =========================================================

local BANK_WARNING_ANGLE = 40
local BANK_WARNING_REPEAT = 3


-- =========================================================
-- STALL
-- =========================================================
--
-- These WILL need tuning after watching your normal speeds.
--
-- Stall now requires:
--   low speed
--   high AoA
--   nose at least slightly raised
-- =========================================================

local STALL_SPEED = 10
local STALL_MIN_SPEED = 2

local STALL_AOA = 15
local STALL_MIN_PITCH = 5

local STALL_WARNING_REPEAT = 1.2


-- =========================================================
-- OVERSPEED
-- =========================================================
--
-- Watch SPD during a normal flight and adjust this.
-- =========================================================

local OVERSPEED_SPEED = 50
local OVERSPEED_REPEAT = 1.0


-- =========================================================
-- SINK RATE
-- =========================================================

local SINK_RATE_THRESHOLD = -8
local SINK_RATE_MAX_AGL = 40
local SINK_RATE_REPEAT = 2.5


-- =========================================================
-- PULL UP
-- =========================================================
--
-- Instead of only looking at vertical speed, this estimates
-- how many seconds remain before reaching runway level.
-- =========================================================

local PULL_UP_TIME_TO_GROUND = 2.2
local PULL_UP_MIN_DESCENT = -4
local PULL_UP_REPEAT = 1.5


-- =========================================================
-- TERRAIN
-- =========================================================
--
-- Outside airport radius:
--
-- Optical sensor sees ANY block within its range
-- =
-- TERRAIN TERRAIN
-- =========================================================

local TERRAIN_REPEAT = 1.2


-- =========================================================
-- RETARD
-- =========================================================

local RETARD_AGL = 5

local RETARD_THRUST_THRESHOLD = 2

local RETARD_REPEAT = 1.2


-- =========================================================
-- AUDIO
-- =========================================================

local SOUND_BANK =
    "bank_angle.dfpwm"

local SOUND_STALL =
    "stall.dfpwm"

local SOUND_OVERSPEED =
    "overspeed.dfpwm"

local SOUND_SINK_RATE =
    "sink_rate.dfpwm"

local SOUND_PULL_UP =
    "pull_up.dfpwm"

local SOUND_TERRAIN =
    "terrain.dfpwm"

local SOUND_APPROACHING_MINIMUMS =
    "approaching_minimums.dfpwm"

local SOUND_MINIMUMS =
    "minimums.dfpwm"

local SOUND_RETARD =
    "retard.dfpwm"


local ALTITUDE_CALLOUTS = {

    {
        altitude = 30,
        sound = "30.dfpwm"
    },

    {
        altitude = 20,
        sound = "20.dfpwm",
        after = SOUND_APPROACHING_MINIMUMS
    },

    {
        altitude = 10,
        sound = "10.dfpwm",
        after = SOUND_MINIMUMS
    }

}


-- =========================================================
-- FIND PERIPHERALS
-- =========================================================

local monitor =
    peripheral.find("monitor")

local speaker =
    peripheral.find("speaker")

local optical =
    peripheral.find("optical_sensor")


-- Fallback: find optical sensor based on methods
if not optical then

    for _, name in ipairs(peripheral.getNames()) do

        local p =
            peripheral.wrap(name)

        if
            p
            and type(p.hasHit) == "function"
            and type(p.getDistance) == "function"
        then

            optical = p
            break

        end

    end

end


if not monitor then
    error("No monitor found")
end

if not speaker then
    error("No speaker found")
end

if not optical then
    error("No optical sensor found")
end

if not sublevel then
    error("CC:Sable sublevel API not found")
end


-- =========================================================
-- MONITOR SETUP
-- =========================================================

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)

local width, height =
    monitor.getSize()


-- =========================================================
-- GENERAL HELPERS
-- =========================================================

local function round(n)

    if n >= 0 then
        return math.floor(n + 0.5)
    else
        return math.ceil(n - 0.5)
    end

end


local function clamp(n, minimum, maximum)

    return math.max(
        minimum,
        math.min(maximum, n)
    )

end


local function normalizeDegrees(angle)

    angle =
        angle % 360

    if angle > 180 then
        angle = angle - 360
    end

    return angle

end


local function atan2(y, x)

    if math.atan2 then
        return math.atan2(y, x)
    end

    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    end

    return 0

end


local function clearRow(y, background)

    monitor.setBackgroundColor(background)
    monitor.setCursorPos(1, y)

    monitor.write(
        string.rep(" ", width)
    )

end


local function writeLeft(
    y,
    text,
    textColor,
    background
)

    monitor.setTextColor(
        textColor or colors.white
    )

    monitor.setBackgroundColor(
        background or colors.black
    )

    monitor.setCursorPos(1, y)

    monitor.write(
        string.sub(text, 1, width)
    )

end


local function writeRight(
    y,
    text,
    textColor,
    background
)

    monitor.setTextColor(
        textColor or colors.white
    )

    monitor.setBackgroundColor(
        background or colors.black
    )

    local x =
        width - #text + 1

    if x < 1 then
        x = 1
    end

    monitor.setCursorPos(x, y)

    monitor.write(
        string.sub(text, 1, width)
    )

end


local function writeCenter(
    y,
    text,
    textColor,
    background
)

    monitor.setTextColor(
        textColor or colors.white
    )

    monitor.setBackgroundColor(
        background or colors.black
    )

    local x =
        math.floor(
            (width - #text) / 2
        ) + 1

    if x < 1 then
        x = 1
    end

    monitor.setCursorPos(x, y)

    monitor.write(
        string.sub(text, 1, width)
    )

end


-- =========================================================
-- AUDIO QUEUE
-- =========================================================

local soundQueue = {}

local currentlyPlaying = nil

local queueOrder = 0


local function soundAlreadyQueued(path)

    if currentlyPlaying == path then
        return true
    end


    for _, sound in ipairs(soundQueue) do

        if sound.path == path then
            return true
        end

    end


    return false

end


local function queueSound(
    path,
    priority
)

    if not fs.exists(path) then
        return
    end


    if soundAlreadyQueued(path) then
        return
    end


    queueOrder =
        queueOrder + 1


    table.insert(
        soundQueue,
        {
            path = path,
            priority = priority or 1,
            order = queueOrder
        }
    )


    table.sort(
        soundQueue,

        function(a, b)

            if a.priority == b.priority then
                return a.order < b.order
            end

            return a.priority > b.priority

        end
    )

end


local function playSound(path)

    currentlyPlaying =
        path


    local file =
        fs.open(path, "rb")


    if not file then

        currentlyPlaying =
            nil

        return

    end


    local decoder =
        dfpwm.make_decoder()


    while true do

        local chunk =
            file.read(
                16 * 1024
            )


        if not chunk then
            break
        end


        local buffer =
            decoder(chunk)


        while not speaker.playAudio(buffer) do

            os.pullEvent(
                "speaker_audio_empty"
            )

        end

    end


    file.close()

    currentlyPlaying =
        nil

end


local function audioLoop()

    while true do

        if #soundQueue > 0 then

            local sound =
                table.remove(
                    soundQueue,
                    1
                )


            playSound(
                sound.path
            )

        else

            sleep(0.05)

        end

    end

end


-- =========================================================
-- THRUST
-- =========================================================

local sides = {
    "top",
    "bottom",
    "left",
    "right",
    "front",
    "back"
}


local function getThrust()

    if THRUST_SIDE then

        return redstone.getAnalogInput(
            THRUST_SIDE
        )

    end


    local strongest = 0


    for _, side in ipairs(sides) do

        -- Ignore monitor, speaker, optical sensor etc.
        if not peripheral.isPresent(side) then

            local value =
                redstone.getAnalogInput(side)


            if value > strongest then
                strongest = value
            end

        end

    end


    return strongest

end


-- =========================================================
-- AIRPORT SYSTEM
-- =========================================================

local function getClosestAirport(position)

    local closestName = nil
    local closest = nil

    local closestDistance =
        math.huge


    for name, airport in pairs(AIRPORTS) do

        local dx =
            position.x
            - airport.x

        local dz =
            position.z
            - airport.z


        local distance =
            math.sqrt(
                dx * dx
                +
                dz * dz
            )


        if distance < closestDistance then

            closestName =
                name

            closest =
                airport

            closestDistance =
                distance

        end

    end


    return
        closestName,
        closest,
        closestDistance

end


-- =========================================================
-- WARNING DISPLAY
-- =========================================================

local warningText = nil
local warningUntil = 0
local warningColor = colors.red


local function showWarning(
    text,
    duration,
    color
)

    warningText =
        text

    warningUntil =
        os.clock()
        + duration

    warningColor =
        color
        or colors.red

end


-- =========================================================
-- ARTIFICIAL HORIZON
-- =========================================================

local ladderAngles = {
    -30,
    -20,
    -10,
    10,
    20,
    30
}


local function drawHorizon(
    bank,
    pitch
)

    local top = 3

    local bottom =
        height - 2


    local centerX =
        (width + 1) / 2

    local centerY =
        (top + bottom) / 2


    local visualBank =
        clamp(
            bank,
            -80,
            80
        )


    local slope =
        math.tan(
            math.rad(
                -visualBank
            )
        )
        * 0.5


    local pitchOffset =
        pitch
        /
        PITCH_DEGREES_PER_ROW


    for y = top, bottom do

        local chars = {}
        local foreground = {}
        local background = {}


        for x = 1, width do

            local horizonY =
                centerY
                + pitchOffset
                + slope
                * (x - centerX)


            if y < horizonY then

                background[x] =
                    colors.toBlit(
                        colors.lightBlue
                    )

            else

                background[x] =
                    colors.toBlit(
                        colors.brown
                    )

            end


            chars[x] = " "

            foreground[x] =
                colors.toBlit(
                    colors.white
                )


            -- =====================================
            -- PITCH LADDER
            -- =====================================

            for _, ladderAngle
                in ipairs(ladderAngles)
            do

                local ladderY =
                    horizonY
                    -
                    (
                        ladderAngle
                        /
                        PITCH_DEGREES_PER_ROW
                    )


                local halfWidth = 2

                if
                    math.abs(ladderAngle)
                    == 20
                then

                    halfWidth = 3

                elseif
                    math.abs(ladderAngle)
                    == 30
                then

                    halfWidth = 4

                end


                if
                    math.abs(
                        x - centerX
                    )
                    <= halfWidth

                    and

                    math.abs(
                        y - ladderY
                    )
                    < 0.30
                then

                    chars[x] =
                        ladderAngle > 0
                        and "="
                        or "-"

                end

            end


            -- Main horizon overrides ladder
            if
                math.abs(
                    y - horizonY
                )
                < 0.40
            then

                chars[x] = "-"

            end

        end


        monitor.setCursorPos(
            1,
            y
        )


        monitor.blit(
            table.concat(chars),
            table.concat(foreground),
            table.concat(background)
        )

    end


    -- Fixed aircraft symbol

    local aircraftY =
        round(centerY)


    local marker =
        "--+--"


    local markerX =
        math.floor(
            (width - #marker) / 2
        )
        + 1


    monitor.setCursorPos(
        markerX,
        aircraftY
    )


    monitor.setTextColor(
        colors.yellow
    )

    monitor.setBackgroundColor(
        colors.black
    )

    monitor.write(marker)

end


-- =========================================================
-- BANK SCALE
-- =========================================================

local function drawBankScale(bank)

    clearRow(
        2,
        colors.black
    )


    local scaleLimit = 60


    local ticks = {

        {-60, "|"},
        {-45, "."},
        {-30, "|"},
        {-20, "."},
        {-10, "."},

        {0, "|"},

        {10, "."},
        {20, "."},
        {30, "|"},
        {45, "."},
        {60, "|"}

    }


    monitor.setTextColor(
        colors.white
    )

    monitor.setBackgroundColor(
        colors.black
    )


    for _, tick in ipairs(ticks) do

        local angle =
            tick[1]

        local symbol =
            tick[2]


        local x =
            round(
                1
                +
                (
                    (angle + scaleLimit)
                    /
                    (scaleLimit * 2)
                )
                *
                (width - 1)
            )


        x =
            clamp(
                x,
                1,
                width
            )


        monitor.setCursorPos(
            x,
            2
        )

        monitor.write(symbol)

    end


    -- Bank pointer

    local pointerBank =
        clamp(
            bank,
            -scaleLimit,
            scaleLimit
        )


    local pointerX =
        round(
            1
            +
            (
                (pointerBank + scaleLimit)
                /
                (scaleLimit * 2)
            )
            *
            (width - 1)
        )


    pointerX =
        clamp(
            pointerX,
            1,
            width
        )


    monitor.setCursorPos(
        pointerX,
        2
    )

    monitor.setTextColor(
        colors.yellow
    )

    monitor.write("^")

end


-- =========================================================
-- WARNING STATE
-- =========================================================

local lastBank = -100
local lastStall = -100
local lastOverspeed = -100
local lastSinkRate = -100
local lastPullUp = -100
local lastTerrain = -100
local lastRetard = -100

local previousAGL = nil
local previousAirport = nil


-- =========================================================
-- FLIGHT DATA
-- =========================================================

local function getFlightData()

    local pose =
        sublevel.getLogicalPose()


    local velocity =
        sublevel.getLinearVelocity()


    local euler = {
        pose.orientation:toEuler()
    }


    local rawBank =
        math.deg(
            euler[BANK_EULER_AXIS]
        )


    local rawPitch =
        math.deg(
            euler[PITCH_EULER_AXIS]
        )


    local bank =
        normalizeDegrees(
            (
                rawBank
                - BANK_ZERO_DEG
            )
            * BANK_SIGN
        )


    local pitch =
        normalizeDegrees(
            (
                rawPitch
                - PITCH_ZERO_DEG
            )
            * PITCH_SIGN
        )


    local speed =
        math.sqrt(
            velocity.x * velocity.x
            +
            velocity.y * velocity.y
            +
            velocity.z * velocity.z
        )


    local horizontalSpeed =
        math.sqrt(
            velocity.x * velocity.x
            +
            velocity.z * velocity.z
        )


    local verticalSpeed =
        velocity.y


    local flightPathAngle =
        math.deg(
            atan2(
                verticalSpeed,
                horizontalSpeed
            )
        )


    local aoa =
        normalizeDegrees(
            pitch
            -
            flightPathAngle
        )


    return {

        pose = pose,

        velocity = velocity,

        altitude =
            pose.position.y,

        bank = bank,

        pitch = pitch,

        speed = speed,

        verticalSpeed =
            verticalSpeed,

        horizontalSpeed =
            horizontalSpeed,

        flightPathAngle =
            flightPathAngle,

        aoa = aoa

    }

end


-- =========================================================
-- WARNINGS
-- =========================================================

local function updateWarnings(
    data,
    thrust
)

    local now =
        os.clock()


    local airportName,
          airport,
          airportDistance =
        getClosestAirport(
            data.pose.position
        )


    local insideAirport =
        airport
        and
        airportDistance
        <= airport.radius


    local agl = nil


    if insideAirport then

        agl =
            data.altitude
            -
            airport.elevation

    end


    -- =============================================
    -- OPTICAL TERRAIN
    -- =============================================

    local terrainDetected =
        false

    local terrainDistance =
        nil


    if not insideAirport then

        terrainDetected =
            optical.hasHit()


        if terrainDetected then

            terrainDistance =
                optical.getDistance()

        end

    end


    -- =============================================
    -- PULL UP
    -- =============================================

    local timeToGround =
        math.huge


    if
        agl
        and agl > 0
        and data.verticalSpeed < 0
    then

        timeToGround =
            agl
            /
            (-data.verticalSpeed)

    end


    local pullUp =
        agl
        and agl > 0

        and

        data.verticalSpeed
        <= PULL_UP_MIN_DESCENT

        and

        timeToGround
        <= PULL_UP_TIME_TO_GROUND


    -- =============================================
    -- STALL
    -- =============================================

    local stall =
        data.speed
            >= STALL_MIN_SPEED

        and

        data.speed
            <= STALL_SPEED

        and

        data.aoa
            >= STALL_AOA

        and

        data.pitch
            >= STALL_MIN_PITCH


    -- =============================================
    -- OVERSPEED
    -- =============================================

    local overspeed =
        data.speed
        >= OVERSPEED_SPEED


    -- =============================================
    -- SINK RATE
    -- =============================================

    local sinkRate =
        agl
        and agl > 0

        and

        agl
        <= SINK_RATE_MAX_AGL

        and

        data.verticalSpeed
        <= SINK_RATE_THRESHOLD


    -- =============================================
    -- BANK ANGLE
    -- =============================================

    local bankAngle =
        math.abs(
            data.bank
        )
        >= BANK_WARNING_ANGLE


    -- =============================================
    -- RETARD
    -- =============================================

    local retard =
        agl
        and agl > 0

        and

        agl <= RETARD_AGL

        and

        data.verticalSpeed < 0

        and

        thrust
        > RETARD_THRUST_THRESHOLD


    -- =====================================================
    -- WARNING PRIORITY
    -- =====================================================

    -- PULL UP
    if pullUp then

        showWarning(
            "PULL UP",
            0.5,
            colors.red
        )


        if
            now - lastPullUp
            >= PULL_UP_REPEAT
        then

            queueSound(
                SOUND_PULL_UP,
                100
            )

            lastPullUp = now

        end


    -- TERRAIN
    elseif terrainDetected then

        showWarning(
            "TERRAIN",
            0.5,
            colors.red
        )


        if
            now - lastTerrain
            >= TERRAIN_REPEAT
        then

            queueSound(
                SOUND_TERRAIN,
                95
            )

            lastTerrain = now

        end


    -- STALL
    elseif stall then

        showWarning(
            "STALL",
            0.5,
            colors.red
        )


        if
            now - lastStall
            >= STALL_WARNING_REPEAT
        then

            queueSound(
                SOUND_STALL,
                90
            )

            lastStall = now

        end


    -- OVERSPEED
    elseif overspeed then

        showWarning(
            "OVERSPEED",
            0.5,
            colors.red
        )


        if
            now - lastOverspeed
            >= OVERSPEED_REPEAT
        then

            queueSound(
                SOUND_OVERSPEED,
                85
            )

            lastOverspeed = now

        end


    -- SINK RATE
    elseif sinkRate then

        showWarning(
            "SINK RATE",
            0.5,
            colors.orange
        )


        if
            now - lastSinkRate
            >= SINK_RATE_REPEAT
        then

            queueSound(
                SOUND_SINK_RATE,
                80
            )

            lastSinkRate = now

        end


    -- BANK ANGLE
    elseif bankAngle then

        showWarning(
            "BANK ANGLE",
            0.5,
            colors.orange
        )


        if
            now - lastBank
            >= BANK_WARNING_REPEAT
        then

            queueSound(
                SOUND_BANK,
                60
            )

            lastBank = now

        end


    -- RETARD
    elseif retard then

        showWarning(
            "RETARD",
            0.5,
            colors.yellow
        )


        if
            now - lastRetard
            >= RETARD_REPEAT
        then

            queueSound(
                SOUND_RETARD,
                20
            )

            lastRetard = now

        end

    end


    -- =====================================================
    -- ALTITUDE CALLOUTS
    -- =====================================================

    if insideAirport then

        -- Reset crossing detection if we changed airports.
        if previousAirport ~= airportName then

            previousAGL = nil
            previousAirport = airportName

        end


        if
            previousAGL
            and
            data.verticalSpeed < 0
        then

            for _, callout
                in ipairs(
                    ALTITUDE_CALLOUTS
                )
            do

                if
                    previousAGL
                    > callout.altitude

                    and

                    agl
                    <= callout.altitude
                then

                    -- Altitude first
                    queueSound(
                        callout.sound,
                        30
                    )


                    -- Then:
                    -- APPROACHING MINIMUMS / MINIMUMS
                    if callout.after then

                        queueSound(
                            callout.after,
                            30
                        )

                    end

                end

            end

        end


        previousAGL =
            agl

    else

        previousAGL =
            nil

        previousAirport =
            nil

    end


    return {

        airportName =
            airportName,

        airport =
            airport,

        airportDistance =
            airportDistance,

        insideAirport =
            insideAirport,

        agl =
            agl,

        terrainDetected =
            terrainDetected,

        terrainDistance =
            terrainDistance,

        timeToGround =
            timeToGround

    }

end


-- =========================================================
-- DISPLAY
-- =========================================================

local function drawDisplay()

    local data =
        getFlightData()


    local thrust =
        getThrust()


    local warningData =
        updateWarnings(
            data,
            thrust
        )


    -- =============================================
    -- HORIZON
    -- =============================================

    drawHorizon(
        data.bank,
        data.pitch
    )


    -- =============================================
    -- BANK SCALE
    -- =============================================

    drawBankScale(
        data.bank
    )


    -- =============================================
    -- TOP ROW
    -- =============================================

    clearRow(
        1,
        colors.black
    )


    writeLeft(
        1,
        string.format(
            "SPD %.1f",
            data.speed
        )
    )


    writeCenter(
        1,
        string.format(
            "ALT %.0f",
            data.altitude
        )
    )


    writeRight(
        1,
        "T "
        .. tostring(thrust)
    )


    -- =============================================
    -- SECOND LAST ROW
    -- AGL + VERTICAL SPEED
    -- =============================================

    clearRow(
        height - 1,
        colors.black
    )


    local aglText


    if warningData.agl then

        local shortName =
            string.sub(
                warningData.airportName,
                1,
                5
            )


        aglText =
            "AGL "
            .. tostring(
                round(
                    warningData.agl
                )
            )
            .. " "
            .. shortName

    else

        aglText =
            "AGL --"

    end


    writeLeft(
        height - 1,
        aglText
    )


    writeRight(
        height - 1,

        string.format(
            "VS %+.1f",
            data.verticalSpeed
        )
    )


    -- =============================================
    -- LAST ROW
    -- BANK / PITCH / AOA
    -- =============================================

    clearRow(
        height,
        colors.black
    )


    local attitudeText =
        string.format(
            "BNK %+.0f PIT %+.0f AOA %.0f",
            data.bank,
            data.pitch,
            data.aoa
        )


    writeCenter(
        height,
        attitudeText,
        colors.white,
        colors.black
    )


    -- =============================================
    -- WARNING OVER BANK SCALE
    -- =============================================

    if
        warningText
        and
        os.clock()
        < warningUntil
    then

        clearRow(
            2,
            colors.black
        )


        writeCenter(
            2,
            warningText,
            warningColor,
            colors.black
        )

    else

        warningText =
            nil

    end

end


-- =========================================================
-- DISPLAY LOOP
-- =========================================================

local function displayLoop()

    monitor.setBackgroundColor(
        colors.black
    )

    monitor.clear()


    while true do

        drawDisplay()

        sleep(0.05)

    end

end


-- =========================================================
-- START
-- =========================================================

parallel.waitForAny(
    displayLoop,
    audioLoop
)
