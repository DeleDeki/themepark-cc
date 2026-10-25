-- =========================================================
-- SMALL PLANE COCKPIT - CC:SABLE V4
-- =========================================================

local dfpwm = require("cc.audio.dfpwm")
local aeroApi = aero or aerodynamics

if not aeroApi then
    error("CC:Sable aero API not found")
end


-- =========================================================
-- AIRPORTS
-- =========================================================

local AIRPORTS = {

    SPAWN = {
        x = 97,
        z = 329,
        elevation = 62,
        radius = 500
    },

    HOME = {
        x = -657,
        z = -312,
        elevation = 71,
        radius = 500
    },

    THEMEPARK = {
        x = 661,
        z = -756,
        elevation = 65,
        radius = 700
    },

}


-- =========================================================
-- ORIENTATION / DISPLAY
-- =========================================================

local BANK_EULER_AXIS = 1
local PITCH_EULER_AXIS = 3

local BANK_SIGN = 1
local PITCH_SIGN = 1

local BANK_ZERO_DEG = 0
local PITCH_ZERO_DEG = 0

local PITCH_DEGREES_PER_ROW = 10


-- =========================================================
-- BANK WARNING
-- =========================================================

local BANK_WARNING_ANGLE = 40
local BANK_WARNING_REPEAT = 3


-- =========================================================
-- STALL
-- =========================================================
--
-- IMPORTANT:
--
-- Stall is NO LONGER simply:
--
--      slow speed = STALL
--
-- A steep actual climb first "arms" the stall detector.
--
-- After that, if:
--
--      climb rate collapses
--      OR
--      vertical speed becomes very low
--
-- while pressure-adjusted speed has fallen enough,
-- STALL is triggered.
--
-- This should catch your:
--
--      rocket climb
--      -> speed bleeds
--      -> climb stops
--      -> aircraft falls
--
-- without screaming during ordinary slow level flight.
-- =========================================================

local STALL_MIN_SPEED = 2

-- Actual direction of travel must reach this climb angle
-- to arm the detector.
local STALL_CLIMB_ARM_ANGLE = 30

-- Once armed, remain armed for this many seconds.
-- This allows STALL to keep detecting through the apex
-- even when the flight path starts dropping again.
local STALL_ARM_HOLD = 3.0

-- Pressure-adjusted speed threshold.
local STALL_EFFECTIVE_SPEED = 32

-- Negative vertical acceleration means climb performance
-- is collapsing.
local STALL_VERTICAL_ACCEL = -0.8

-- If an armed aircraft reaches this low VS while its
-- effective speed is also low, trigger STALL.
local STALL_LOW_VS = 4

local STALL_WARNING_REPEAT = 1.2


-- Pressure at Y=63 is treated as our normal reference.
local PRESSURE_REFERENCE_ALTITUDE = 63


-- =========================================================
-- OVERSPEED
-- =========================================================

local OVERSPEED_SPEED = 40
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
-- PULL UP is now terrain based.
--
-- It is COMPLETELY DISABLED inside registered airport
-- radii, exactly like TERRAIN.
--
-- Outside airports:
--
-- Optical hit = TERRAIN
-- Optical hit <= 7 blocks = PULL UP
-- =========================================================

local PULL_UP_TERRAIN_DISTANCE = 7
local PULL_UP_REPEAT = 1.5


-- =========================================================
-- TERRAIN
-- =========================================================

local TERRAIN_REPEAT = 1.2

-- Prevent crashed/stationary aircraft endlessly screaming.
local TERRAIN_MIN_SPEED = 0.5
local TERRAIN_MIN_VERTICAL_SPEED = 0.2


-- =========================================================
-- RETARD
-- =========================================================

local RETARD_AGL = 5

-- 0 = lowest running thrust.
-- 1-13 = increasing power.
-- 14 / 15 = OFF.
local RETARD_THRUST_THRESHOLD = 0

local RETARD_REPEAT = 1.2


-- =========================================================
-- SOUND FILES
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
-- PERIPHERALS
-- =========================================================

local monitor =
    peripheral.find("monitor")

local speaker =
    peripheral.find("speaker")

local optical =
    peripheral.find("optical_sensor")


-- Fallback optical detection.
if not optical then

    for _, name in ipairs(
        peripheral.getNames()
    ) do

        local p =
            peripheral.wrap(name)

        if
            p
            and
            type(p.hasHit) == "function"
            and
            type(p.getDistance) == "function"
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
-- MONITOR
-- =========================================================

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)

local width, height =
    monitor.getSize()


-- =========================================================
-- HELPERS
-- =========================================================

local function round(n)

    if n >= 0 then
        return math.floor(n + 0.5)
    end

    return math.ceil(n - 0.5)

end


local function clamp(
    n,
    low,
    high
)

    return math.max(
        low,
        math.min(
            high,
            n
        )
    )

end


local function normalizeDegrees(angle)

    angle =
        angle % 360

    if angle > 180 then

        angle =
            angle - 360

    end

    return angle

end


local function atan2(
    y,
    x
)

    if math.atan2 then

        return math.atan2(
            y,
            x
        )

    end


    if x > 0 then

        return math.atan(
            y / x
        )

    elseif
        x < 0
        and
        y >= 0
    then

        return math.atan(
            y / x
        )
        + math.pi

    elseif
        x < 0
        and
        y < 0
    then

        return math.atan(
            y / x
        )
        - math.pi

    elseif
        x == 0
        and
        y > 0
    then

        return math.pi / 2

    elseif
        x == 0
        and
        y < 0
    then

        return -math.pi / 2

    end


    return 0

end


local function clearRow(
    y,
    bg
)

    monitor.setBackgroundColor(bg)

    monitor.setCursorPos(
        1,
        y
    )

    monitor.write(
        string.rep(
            " ",
            width
        )
    )

end


local function writeAt(
    x,
    y,
    text,
    fg,
    bg
)

    monitor.setCursorPos(
        x,
        y
    )

    monitor.setTextColor(
        fg
        or colors.white
    )

    monitor.setBackgroundColor(
        bg
        or colors.black
    )

    monitor.write(text)

end


local function writeCenter(
    y,
    text,
    fg,
    bg
)

    local x =
        math.floor(
            (
                width
                -
                #text
            )
            / 2
        )
        + 1


    if x < 1 then
        x = 1
    end


    writeAt(
        x,
        y,
        string.sub(
            text,
            1,
            width
        ),
        fg,
        bg
    )

end


local function drawPairRow(
    y,
    leftText,
    rightText,
    compactLeft,
    compactRight
)

    clearRow(
        y,
        colors.black
    )


    if
        #leftText
        +
        #rightText
        +
        1
        >
        width
    then

        leftText =
            compactLeft
            or leftText

        rightText =
            compactRight
            or rightText

    end


    writeAt(
        1,
        y,
        leftText,
        colors.white,
        colors.black
    )


    local rightX =
        width
        -
        #rightText
        +
        1


    if
        rightX
        <=
        #leftText
    then

        rightX =
            #leftText
            + 1

    end


    if rightX <= width then

        writeAt(
            rightX,
            y,
            rightText,
            colors.white,
            colors.black
        )

    end

end


-- =========================================================
-- AUDIO QUEUE
-- =========================================================

local soundQueue = {}

local currentlyPlaying =
    nil

local queueOrder =
    0


local function soundAlreadyQueued(path)

    if currentlyPlaying == path then
        return true
    end


    for _, sound
        in ipairs(
            soundQueue
        )
    do

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
        queueOrder
        + 1


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

        function(
            a,
            b
        )

            if
                a.priority
                ==
                b.priority
            then

                return
                    a.order
                    <
                    b.order

            end


            return
                a.priority
                >
                b.priority

        end

    )

end


local function playSound(path)

    currentlyPlaying =
        path


    local file =
        fs.open(
            path,
            "rb"
        )


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


        while
            not speaker.playAudio(
                buffer
            )
        do

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

        if
            #soundQueue
            >
            0
        then

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
-- THROTTLE
-- =========================================================

local sides = {

    "top",
    "bottom",
    "left",
    "right",
    "front",
    "back"

}


local function getRawThrust()

    local strongest =
        0


    for _, side
        in ipairs(
            sides
        )
    do

        if
            not peripheral.isPresent(
                side
            )
        then

            local value =
                redstone.getAnalogInput(
                    side
                )


            if
                value
                >
                strongest
            then

                strongest =
                    value

            end

        end

    end


    return strongest

end


local function decodeThrust(raw)

    -- 0  = minimum running power
    -- 13 = maximum
    -- 14 = OFF
    -- 15 = OFF

    return {

        raw = raw,

        power =
            raw >= 14
            and 0
            or raw,

        off =
            raw >= 14

    }

end


-- =========================================================
-- AIRPORT SYSTEM
-- =========================================================

local function getClosestAirport(
    position
)

    local closestName =
        nil

    local closest =
        nil

    local closestDistance =
        math.huge


    for name, airport
        in pairs(
            AIRPORTS
        )
    do

        local dx =
            position.x
            -
            airport.x

        local dz =
            position.z
            -
            airport.z


        local distance =
            math.sqrt(
                dx * dx
                +
                dz * dz
            )


        if
            distance
            <
            closestDistance
        then

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

local warningText =
    nil

local warningUntil =
    0

local warningColor =
    colors.red


local function showWarning(
    text,
    duration,
    color
)

    warningText =
        text

    warningUntil =
        os.clock()
        +
        duration

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

    local top =
        3

    local bottom =
        height - 2


    local centerX =
        (
            width
            +
            1
        )
        / 2

    local centerY =
        (
            top
            +
            bottom
        )
        / 2


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


    for y =
        top,
        bottom
    do

        local chars = {}
        local fg = {}
        local bg = {}


        for x =
            1,
            width
        do

            local horizonY =
                centerY
                +
                pitchOffset
                +
                slope
                *
                (
                    x
                    -
                    centerX
                )


            if
                y
                <
                horizonY
            then

                bg[x] =
                    colors.toBlit(
                        colors.lightBlue
                    )

            else

                bg[x] =
                    colors.toBlit(
                        colors.brown
                    )

            end


            chars[x] =
                " "

            fg[x] =
                colors.toBlit(
                    colors.white
                )


            -- Pitch ladder
            for _, ladderAngle
                in ipairs(
                    ladderAngles
                )
            do

                local ladderY =
                    horizonY
                    -
                    (
                        ladderAngle
                        /
                        PITCH_DEGREES_PER_ROW
                    )


                local halfWidth =
                    2


                if
                    math.abs(
                        ladderAngle
                    )
                    ==
                    20
                then

                    halfWidth =
                        3

                elseif
                    math.abs(
                        ladderAngle
                    )
                    ==
                    30
                then

                    halfWidth =
                        4

                end


                if
                    math.abs(
                        x
                        -
                        centerX
                    )
                    <=
                    halfWidth

                    and

                    math.abs(
                        y
                        -
                        ladderY
                    )
                    <
                    0.30
                then

                    chars[x] =
                        ladderAngle > 0
                        and "="
                        or "-"

                end

            end


            -- Main horizon
            if
                math.abs(
                    y
                    -
                    horizonY
                )
                <
                0.40
            then

                chars[x] =
                    "-"

            end

        end


        monitor.setCursorPos(
            1,
            y
        )


        monitor.blit(
            table.concat(
                chars
            ),
            table.concat(
                fg
            ),
            table.concat(
                bg
            )
        )

    end


    local marker =
        "--+--"


    local markerX =
        math.floor(
            (
                width
                -
                #marker
            )
            / 2
        )
        +
        1


    local aircraftY =
        round(
            centerY
        )


    writeAt(
        markerX,
        aircraftY,
        marker,
        colors.yellow,
        colors.black
    )

end


-- =========================================================
-- BANK SCALE
-- =========================================================

local function drawBankScale(bank)

    clearRow(
        2,
        colors.black
    )


    local scaleLimit =
        60


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


    for _, tick
        in ipairs(
            ticks
        )
    do

        local x =
            round(
                1
                +
                (
                    (
                        tick[1]
                        +
                        scaleLimit
                    )
                    /
                    (
                        scaleLimit
                        *
                        2
                    )
                )
                *
                (
                    width
                    -
                    1
                )
            )


        x =
            clamp(
                x,
                1,
                width
            )


        writeAt(
            x,
            2,
            tick[2],
            colors.white,
            colors.black
        )

    end


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
                (
                    pointerBank
                    +
                    scaleLimit
                )
                /
                (
                    scaleLimit
                    *
                    2
                )
            )
            *
            (
                width
                -
                1
            )
        )


    pointerX =
        clamp(
            pointerX,
            1,
            width
        )


    writeAt(
        pointerX,
        2,
        "^",
        colors.yellow,
        colors.black
    )

end


-- =========================================================
-- PRESSURE
-- =========================================================

local function getPressureRatio(
    position
)

    local currentPressure =
        1

    local referencePressure =
        1


    local okCurrent,
          resultCurrent =
        pcall(
            aeroApi.getAirPressure,
            position
        )


    if
        okCurrent
        and
        type(
            resultCurrent
        )
        ==
        "number"
        and
        resultCurrent
        >
        0
    then

        currentPressure =
            resultCurrent

    end


    local referencePosition =
        vector.new(

            position.x,

            PRESSURE_REFERENCE_ALTITUDE,

            position.z

        )


    local okReference,
          resultReference =
        pcall(
            aeroApi.getAirPressure,
            referencePosition
        )


    if
        okReference
        and
        type(
            resultReference
        )
        ==
        "number"
        and
        resultReference
        >
        0
    then

        referencePressure =
            resultReference

    end


    return clamp(

        currentPressure
        /
        referencePressure,

        0.05,

        2

    )

end


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

            euler[
                BANK_EULER_AXIS
            ]

        )


    local rawPitch =
        math.deg(

            euler[
                PITCH_EULER_AXIS
            ]

        )


    local bank =
        normalizeDegrees(

            (
                rawBank
                -
                BANK_ZERO_DEG
            )

            *

            BANK_SIGN

        )


    local pitch =
        normalizeDegrees(

            (
                rawPitch
                -
                PITCH_ZERO_DEG
            )

            *

            PITCH_SIGN

        )


    local speed =
        math.sqrt(

            velocity.x
            *
            velocity.x

            +

            velocity.y
            *
            velocity.y

            +

            velocity.z
            *
            velocity.z

        )


    local horizontalSpeed =
        math.sqrt(

            velocity.x
            *
            velocity.x

            +

            velocity.z
            *
            velocity.z

        )


    local verticalSpeed =
        velocity.y


    -- Actual direction of movement.
    --
    -- 0   = level
    -- 45  = steep climb
    -- 90  = straight upward
    -- -45 = steep descent
    local flightPathAngle =
        math.deg(

            atan2(

                verticalSpeed,

                horizontalSpeed

            )

        )


    -- Kept for display / future use.
    -- It does NOT independently trigger stall anymore.
    local aoa =
        normalizeDegrees(

            pitch
            -
            flightPathAngle

        )


    local pressureRatio =
        getPressureRatio(
            pose.position
        )


    -- This isn't real indicated airspeed.
    --
    -- It is deliberately a Minecraft/Sable
    -- pressure-adjusted speed used by the stall detector.
    --
    -- Lower pressure at altitude lowers this value.
    local effectiveSpeed =
        speed
        *
        pressureRatio


    return {

        pose =
            pose,

        altitude =
            pose.position.y,

        bank =
            bank,

        pitch =
            pitch,

        speed =
            speed,

        effectiveSpeed =
            effectiveSpeed,

        pressureRatio =
            pressureRatio,

        verticalSpeed =
            verticalSpeed,

        flightPathAngle =
            flightPathAngle,

        aoa =
            aoa

    }

end


-- =========================================================
-- WARNING STATE
-- =========================================================

local lastBank =
    -100

local lastStall =
    -100

local lastOverspeed =
    -100

local lastSinkRate =
    -100

local lastPullUp =
    -100

local lastTerrain =
    -100

local lastRetard =
    -100


local previousAGL =
    nil

local previousAirport =
    nil


local previousAltitude =
    nil

local previousAltitudeTime =
    nil

local altitudeTrendVS =
    0


local previousVerticalSpeed =
    nil

local verticalAcceleration =
    0


-- Timestamp of most recent steep climb.
local lastSteepClimb =
    -100


-- =========================================================
-- WARNING LOGIC
-- =========================================================

local function updateWarnings(
    data,
    thrust
)

    local now =
        os.clock()


    -- =====================================================
    -- MOTION TREND
    -- =====================================================

    if
        previousAltitude
        and
        previousAltitudeTime
    then

        local dt =
            now
            -
            previousAltitudeTime


        if dt > 0 then

            altitudeTrendVS =
                (
                    data.altitude
                    -
                    previousAltitude
                )
                /
                dt


            if previousVerticalSpeed then

                local rawVerticalAcceleration =
                    (
                        data.verticalSpeed
                        -
                        previousVerticalSpeed
                    )
                    /
                    dt


                -- Smooth physics noise.
                verticalAcceleration =
                    verticalAcceleration
                    *
                    0.75

                    +

                    rawVerticalAcceleration
                    *
                    0.25

            end

        end

    end


    previousAltitude =
        data.altitude

    previousAltitudeTime =
        now

    previousVerticalSpeed =
        data.verticalSpeed


    local descending =
        data.verticalSpeed
        <
        -0.05

        and

        altitudeTrendVS
        <
        -0.05


    -- =====================================================
    -- AIRPORT / AGL
    -- =====================================================

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
        <=
        airport.radius


    local agl =
        nil


    if insideAirport then

        agl =
            data.altitude
            -
            airport.elevation

    end


    -- =====================================================
    -- AIRCRAFT MOVING?
    -- =====================================================

    local aircraftMoving =
        data.speed
        >
        TERRAIN_MIN_SPEED

        or

        math.abs(
            data.verticalSpeed
        )
        >
        TERRAIN_MIN_VERTICAL_SPEED


    -- =====================================================
    -- TERRAIN
    -- =====================================================

    local terrainDetected =
        false

    local terrainDistance =
        nil


    -- TERRAIN IS DISABLED AT AIRPORTS.
    if
        not insideAirport

        and

        aircraftMoving
    then

        terrainDetected =
            optical.hasHit()


        if terrainDetected then

            terrainDistance =
                optical.getDistance()

        end

    end


    -- =====================================================
    -- PULL UP
    -- =====================================================
    --
    -- PULL UP IS ALSO DISABLED AT AIRPORTS.
    --
    -- Away from airports:
    --
    -- TERRAIN = sensor sees anything
    -- PULL UP = sensor sees something <= 7 blocks
    -- =====================================================

    local pullUp =
        not insideAirport

        and

        terrainDetected

        and

        terrainDistance ~= nil

        and

        terrainDistance
        <=
        PULL_UP_TERRAIN_DISTANCE


    -- =====================================================
    -- STALL
    -- =====================================================
    --
    -- The old independent AoA stall path is removed.
    --
    -- That was responsible for slow straight flight
    -- sometimes triggering STALL.
    --
    -- Instead:
    --
    -- 1. ACTUAL upward trajectory becomes steep.
    -- 2. Stall system becomes armed.
    -- 3. It remains armed briefly through the apex.
    -- 4. If climb performance collapses while pressure-
    --    adjusted speed is low, STALL sounds.
    -- =====================================================


    if
        data.flightPathAngle
        >=
        STALL_CLIMB_ARM_ANGLE

        and

        data.verticalSpeed
        >
        0
    then

        lastSteepClimb =
            now

    end


    local stallArmed =
        (
            now
            -
            lastSteepClimb
        )
        <=
        STALL_ARM_HOLD


    -- Case 1:
    --
    -- Still climbing but VS is collapsing rapidly.
    local collapsingClimb =
        verticalAcceleration
        <=
        STALL_VERTICAL_ACCEL

        and

        data.effectiveSpeed
        <=
        STALL_EFFECTIVE_SPEED


    -- Case 2:
    --
    -- At/near the top of the climb,
    -- almost no climb left.
    local nearlyOutOfClimb =
        data.verticalSpeed
        <=
        STALL_LOW_VS

        and

        data.effectiveSpeed
        <=
        STALL_EFFECTIVE_SPEED


    local stall =
        data.speed
        >=
        STALL_MIN_SPEED

        and

        stallArmed

        and

        (
            collapsingClimb
            or
            nearlyOutOfClimb
        )


    -- =====================================================
    -- OVERSPEED
    -- =====================================================

    local overspeed =
        data.speed
        >=
        OVERSPEED_SPEED


    -- =====================================================
    -- SINK RATE
    -- =====================================================

    local sinkRate =
        agl

        and

        agl > 0

        and

        descending

        and

        data.verticalSpeed
        <=
        SINK_RATE_THRESHOLD

        and

        agl
        <=
        SINK_RATE_MAX_AGL


    -- =====================================================
    -- BANK ANGLE
    -- =====================================================

    local bankAngle =
        math.abs(
            data.bank
        )
        >=
        BANK_WARNING_ANGLE


    -- =====================================================
    -- RETARD
    -- =====================================================

    local retard =
        agl

        and

        agl > 0

        and

        agl
        <=
        RETARD_AGL

        and

        descending

        -- 14 / 15 count as engine OFF.
        and

        not thrust.off

        -- 0 counts as fully retarded.
        and

        thrust.power
        >
        RETARD_THRUST_THRESHOLD


    -- =====================================================
    -- WARNING PRIORITY
    -- =====================================================

    if pullUp then

        showWarning(
            "PULL UP",
            0.5,
            colors.red
        )


        if
            now
            -
            lastPullUp
            >=
            PULL_UP_REPEAT
        then

            queueSound(
                SOUND_PULL_UP,
                100
            )

            lastPullUp =
                now

        end


    elseif terrainDetected then

        showWarning(
            "TERRAIN",
            0.5,
            colors.red
        )


        if
            now
            -
            lastTerrain
            >=
            TERRAIN_REPEAT
        then

            queueSound(
                SOUND_TERRAIN,
                95
            )

            lastTerrain =
                now

        end


    elseif stall then

        showWarning(
            "STALL",
            0.5,
            colors.red
        )


        if
            now
            -
            lastStall
            >=
            STALL_WARNING_REPEAT
        then

            queueSound(
                SOUND_STALL,
                90
            )

            lastStall =
                now

        end


    elseif overspeed then

        showWarning(
            "OVERSPEED",
            0.5,
            colors.red
        )


        if
            now
            -
            lastOverspeed
            >=
            OVERSPEED_REPEAT
        then

            queueSound(
                SOUND_OVERSPEED,
                85
            )

            lastOverspeed =
                now

        end


    elseif sinkRate then

        showWarning(
            "SINK RATE",
            0.5,
            colors.orange
        )


        if
            now
            -
            lastSinkRate
            >=
            SINK_RATE_REPEAT
        then

            queueSound(
                SOUND_SINK_RATE,
                80
            )

            lastSinkRate =
                now

        end


    elseif bankAngle then

        showWarning(
            "BANK ANGLE",
            0.5,
            colors.orange
        )


        if
            now
            -
            lastBank
            >=
            BANK_WARNING_REPEAT
        then

            queueSound(
                SOUND_BANK,
                60
            )

            lastBank =
                now

        end


    elseif retard then

        showWarning(
            "RETARD",
            0.5,
            colors.yellow
        )


        if
            now
            -
            lastRetard
            >=
            RETARD_REPEAT
        then

            queueSound(
                SOUND_RETARD,
                20
            )

            lastRetard =
                now

        end

    end


    -- =====================================================
    -- AIRPORT ALTITUDE CALLOUTS
    -- =====================================================

    if insideAirport then

        if
            previousAirport
            ~=
            airportName
        then

            previousAGL =
                nil

            previousAirport =
                airportName

        end


        if
            previousAGL
            and
            descending
        then

            for _, callout
                in ipairs(
                    ALTITUDE_CALLOUTS
                )
            do

                if
                    previousAGL
                    >
                    callout.altitude

                    and

                    agl
                    <=
                    callout.altitude
                then

                    queueSound(
                        callout.sound,
                        30
                    )


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

        insideAirport =
            insideAirport,

        airportDistance =
            airportDistance,

        agl =
            agl,

        terrainDetected =
            terrainDetected,

        terrainDistance =
            terrainDistance,

        descending =
            descending,

        verticalAcceleration =
            verticalAcceleration,

        stallArmed =
            stallArmed

    }

end


-- =========================================================
-- DISPLAY
-- =========================================================

local function drawDisplay()

    local data =
        getFlightData()


    local thrust =
        decodeThrust(
            getRawThrust()
        )


    local state =
        updateWarnings(
            data,
            thrust
        )


    -- Artificial horizon
    drawHorizon(
        data.bank,
        data.pitch
    )


    -- Bank indicator
    drawBankScale(
        data.bank
    )


    -- =====================================================
    -- SPEED + ALTITUDE
    -- =====================================================

    local speedNumber =
        tostring(
            round(
                data.speed
            )
        )


    local altitudeNumber =
        tostring(
            round(
                data.altitude
            )
        )


    drawPairRow(

        1,

        "SPD "
        ..
        speedNumber,

        "ALT "
        ..
        altitudeNumber,

        "S"
        ..
        speedNumber,

        "A"
        ..
        altitudeNumber

    )


    -- =====================================================
    -- AGL + VERTICAL SPEED
    -- =====================================================

    local aglText
    local compactAGL


    if state.agl then

        aglText =
            "AGL "
            ..
            tostring(
                round(
                    state.agl
                )
            )


        compactAGL =
            "G"
            ..
            tostring(
                round(
                    state.agl
                )
            )

    else

        aglText =
            "AGL --"

        compactAGL =
            "G--"

    end


    local vsNumber =
        string.format(
            "%+.1f",
            data.verticalSpeed
        )


    drawPairRow(

        height - 1,

        aglText,

        "VS "
        ..
        vsNumber,

        compactAGL,

        "V"
        ..
        vsNumber

    )


    -- =====================================================
    -- BANK / PITCH / RAW THRUST
    -- =====================================================

    clearRow(
        height,
        colors.black
    )


    -- IMPORTANT:
    --
    -- RAW THRUST IS ALWAYS DISPLAYED.
    --
    -- T13
    -- T14
    -- T15
    --
    -- 14 and 15 are still internally understood as OFF.
    local bottomText =
        string.format(

            "B%+.0f P%+.0f T%d",

            data.bank,

            data.pitch,

            thrust.raw

        )


    writeCenter(
        height,
        bottomText,
        colors.white,
        colors.black
    )


    -- =====================================================
    -- WARNING TEXT
    -- =====================================================

    if
        warningText
        and
        os.clock()
        <
        warningUntil
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
-- MAIN LOOPS
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


parallel.waitForAny(
    displayLoop,
    audioLoop
)
