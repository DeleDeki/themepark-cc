-- =========================================================
-- SMALL PLANE COCKPIT V3
-- Artificial Horizon + Altitude + Thrust + GPWS + Stall
-- =========================================================

local dfpwm = require("cc.audio.dfpwm")


-- =========================================================
-- SETTINGS
-- =========================================================

-- GIMBAL
local BANK_AXIS = 1
local PITCH_AXIS = 2

local BANK_SIGN = 1

-- Your plane needs reversed pitch.
local PITCH_SIGN = -1

local PITCH_DEGREES_PER_ROW = 10


-- =========================================================
-- AIRPORT / ALTITUDE
-- =========================================================

-- Your airport / sea level.
local GROUND_LEVEL = 63

local ALTITUDE_CALLOUTS = {
    { altitude = 30, sound = "30.dfpwm" },
    { altitude = 20, sound = "20.dfpwm" },
    { altitude = 10, sound = "10.dfpwm" }
}


-- =========================================================
-- BANK WARNING
-- =========================================================

-- Change to 30, 35, 40 etc.
local BANK_WARNING_ANGLE = 40

-- Seconds before repeating BANK ANGLE.
local BANK_WARNING_REPEAT = 3


-- =========================================================
-- STALL WARNING
-- =========================================================

-- Nose-up angle required before STALL becomes possible.
local STALL_PITCH_ANGLE = 35

-- If vertical speed is below this while pitched up,
-- consider the aircraft to be struggling/stalling.
--
-- 2 means:
-- climbing faster than 2 blocks/sec = no stall warning
-- climbing slower than 2 blocks/sec = stall warning
local STALL_MAX_VERTICAL_SPEED = 2

local STALL_WARNING_REPEAT = 1.5


-- =========================================================
-- SINK RATE
-- =========================================================

-- Blocks per second.
local SINK_RATE_THRESHOLD = -8

-- Only warn below this height above airport level.
local SINK_RATE_MAX_HEIGHT = 40

local SINK_RATE_REPEAT = 3


-- =========================================================
-- PULL UP
-- =========================================================

local PULL_UP_THRESHOLD = -12

local PULL_UP_MAX_HEIGHT = 25

local PULL_UP_REPEAT = 2


-- =========================================================
-- SOUND FILES
-- =========================================================

local SOUND_BANK =
    "bank_angle.dfpwm"

local SOUND_STALL =
    "stall.dfpwm"

local SOUND_SINK_RATE =
    "sink_rate.dfpwm"

local SOUND_PULL_UP =
    "pull_up.dfpwm"


-- =========================================================
-- FIND PERIPHERALS
-- =========================================================

local monitor =
    peripheral.find("monitor")

local gimbal =
    peripheral.find("gimbal_sensor")

local altitudeSensor =
    peripheral.find("altitude_sensor")

local speaker =
    peripheral.find("speaker")


if not monitor then
    error("No monitor found")
end

if not gimbal then
    error("No gimbal sensor found")
end

if not altitudeSensor then
    error("No altitude sensor found")
end

if not speaker then
    error("No speaker found")
end


-- =========================================================
-- MONITOR SETUP
-- =========================================================

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)

local width, height =
    monitor.getSize()


-- =========================================================
-- SOUND QUEUE
-- =========================================================

local soundQueue = {}

local currentlyPlaying = nil


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


local function queueSound(path, priority)

    if not fs.exists(path) then
        return
    end

    if soundAlreadyQueued(path) then
        return
    end

    table.insert(
        soundQueue,
        {
            path = path,
            priority = priority or 1
        }
    )

    table.sort(
        soundQueue,
        function(a, b)
            return a.priority > b.priority
        end
    )

end


local function playSound(path)

    currentlyPlaying = path

    local file =
        fs.open(path, "rb")

    if not file then
        currentlyPlaying = nil
        return
    end


    local decoder =
        dfpwm.make_decoder()


    while true do

        local chunk =
            file.read(16 * 1024)

        if not chunk then
            break
        end


        local buffer =
            decoder(chunk)


        while not speaker.playAudio(buffer) do
            os.pullEvent("speaker_audio_empty")
        end

    end


    file.close()

    currentlyPlaying = nil

end


local function audioLoop()

    while true do

        if #soundQueue > 0 then

            local sound =
                table.remove(soundQueue, 1)

            playSound(sound.path)

        else

            sleep(0.05)

        end

    end

end


-- =========================================================
-- HELPERS
-- =========================================================

local function round(n)

    if n >= 0 then
        return math.floor(n + 0.5)
    else
        return math.ceil(n - 0.5)
    end

end


local function clearRow(y, background)

    monitor.setBackgroundColor(background)

    monitor.setCursorPos(1, y)

    monitor.write(
        string.rep(" ", width)
    )

end


local function centerText(
    y,
    text,
    textColor,
    background
)

    local x =
        math.floor(
            (width - #text) / 2
        ) + 1

    monitor.setBackgroundColor(background)

    monitor.setTextColor(textColor)

    monitor.setCursorPos(x, y)

    monitor.write(text)

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

    local strongest = 0

    for _, side in ipairs(sides) do

        local value =
            redstone.getAnalogInput(side)

        if value > strongest then
            strongest = value
        end

    end

    return strongest

end


-- =========================================================
-- ARTIFICIAL HORIZON
-- =========================================================

local function drawHorizon(bank, pitch)

    local top = 2
    local bottom = height - 1

    local centerX =
        (width + 1) / 2

    local centerY =
        (top + bottom) / 2


    local visualBank =
        math.max(
            -80,
            math.min(80, bank)
        )


    local slope =
        math.tan(
            math.rad(-visualBank)
        ) * 0.5


    local pitchOffset =
        pitch /
        PITCH_DEGREES_PER_ROW


    for y = top, bottom do

        local chars = {}
        local foreground = {}
        local background = {}


        for x = 1, width do

            local horizonY =
                centerY
                + pitchOffset
                + slope * (x - centerX)


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


            if math.abs(
                y - horizonY
            ) < 0.45 then

                chars[x] = "-"

            else

                chars[x] = " "

            end


            foreground[x] =
                colors.toBlit(
                    colors.white
                )

        end


        monitor.setCursorPos(1, y)

        monitor.blit(
            table.concat(chars),
            table.concat(foreground),
            table.concat(background)
        )

    end


    -- Aircraft marker
    local aircraftY =
        round(centerY)

    local marker =
        "--+--"

    local markerX =
        math.floor(
            (width - #marker) / 2
        ) + 1


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

    warningText = text

    warningUntil =
        os.clock() + duration

    warningColor =
        color or colors.red

end


-- =========================================================
-- WARNING STATE
-- =========================================================

local previousAltitude = nil
local previousAGL = nil
local previousTime = nil

local verticalSpeed = 0

local lastBankWarning = -100
local lastStallWarning = -100
local lastSinkWarning = -100
local lastPullUpWarning = -100


-- =========================================================
-- WARNING LOGIC
-- =========================================================

local function updateWarnings(
    altitude,
    bank,
    pitch
)

    local now =
        os.clock()

    local agl =
        altitude - GROUND_LEVEL


    -- =====================================================
    -- VERTICAL SPEED
    -- =====================================================

    if previousAltitude and previousTime then

        local dt =
            now - previousTime

        if dt > 0 then

            local rawVS =
                (altitude - previousAltitude)
                / dt

            -- Smooth the measurement.
            verticalSpeed =
                verticalSpeed * 0.75
                + rawVS * 0.25

        end

    end


    -- =====================================================
    -- CONDITIONS
    -- =====================================================

    local pullUp =
        agl <= PULL_UP_MAX_HEIGHT
        and agl > 0
        and verticalSpeed <= PULL_UP_THRESHOLD


    local stall =
        pitch >= STALL_PITCH_ANGLE
        and verticalSpeed <= STALL_MAX_VERTICAL_SPEED


    local sinkRate =
        agl <= SINK_RATE_MAX_HEIGHT
        and agl > 0
        and verticalSpeed <= SINK_RATE_THRESHOLD


    local bankAngle =
        math.abs(bank)
        >= BANK_WARNING_ANGLE


    -- =====================================================
    -- PULL UP
    -- Priority 100
    -- =====================================================

    if pullUp then

        showWarning(
            "PULL UP",
            1,
            colors.red
        )


        if
            now - lastPullUpWarning
            >= PULL_UP_REPEAT
        then

            queueSound(
                SOUND_PULL_UP,
                100
            )

            lastPullUpWarning = now

        end


    -- =====================================================
    -- STALL
    -- Priority 90
    -- =====================================================

    elseif stall then

        showWarning(
            "STALL",
            1,
            colors.red
        )


        if
            now - lastStallWarning
            >= STALL_WARNING_REPEAT
        then

            queueSound(
                SOUND_STALL,
                90
            )

            lastStallWarning = now

        end


    -- =====================================================
    -- SINK RATE
    -- Priority 80
    -- =====================================================

    elseif sinkRate then

        showWarning(
            "SINK RATE",
            1,
            colors.orange
        )


        if
            now - lastSinkWarning
            >= SINK_RATE_REPEAT
        then

            queueSound(
                SOUND_SINK_RATE,
                80
            )

            lastSinkWarning = now

        end


    -- =====================================================
    -- BANK ANGLE
    -- Priority 60
    -- =====================================================

    elseif bankAngle then

        showWarning(
            "BANK ANGLE",
            1,
            colors.orange
        )


        if
            now - lastBankWarning
            >= BANK_WARNING_REPEAT
        then

            queueSound(
                SOUND_BANK,
                60
            )

            lastBankWarning = now

        end

    end


    -- =====================================================
    -- ALTITUDE CALLOUTS
    -- =====================================================

    if previousAGL then

        -- Only announce while descending.
        if verticalSpeed < 0 then

            -- Don't calmly say "20" while screaming PULL UP.
            if not pullUp then

                for _, callout
                    in ipairs(
                        ALTITUDE_CALLOUTS
                    )
                do

                    if
                        previousAGL
                            > callout.altitude

                        and agl
                            <= callout.altitude
                    then

                        queueSound(
                            callout.sound,
                            20
                        )

                    end

                end

            end

        end

    end


    previousAltitude =
        altitude

    previousAGL =
        agl

    previousTime =
        now

end


-- =========================================================
-- MAIN DISPLAY
-- =========================================================

local function drawDisplay()

    local altitude =
        altitudeSensor.getHeight()


    local angles =
        gimbal.getAngles()


    local bank =
        angles[BANK_AXIS]
        * BANK_SIGN


    local pitch =
        angles[PITCH_AXIS]
        * PITCH_SIGN


    local thrust =
        getThrust()


    -- Warning calculations
    updateWarnings(
        altitude,
        bank,
        pitch
    )


    -- Artificial horizon
    drawHorizon(
        bank,
        pitch
    )


    -- =====================================================
    -- TOP BAR
    -- =====================================================

    clearRow(
        1,
        colors.black
    )


    local altitudeText =
        "ALT "
        .. tostring(
            round(altitude)
        )


    local thrustText =
        "THR "
        .. tostring(thrust)


    monitor.setBackgroundColor(
        colors.black
    )

    monitor.setTextColor(
        colors.white
    )


    monitor.setCursorPos(1, 1)

    monitor.write(
        altitudeText
    )


    monitor.setCursorPos(
        width
        - #thrustText
        + 1,
        1
    )

    monitor.write(
        thrustText
    )


    -- =====================================================
    -- BANK DISPLAY
    -- =====================================================

    clearRow(
        height,
        colors.black
    )


    local bankText =
        string.format(
            "BANK %+.0f",
            bank
        )


    centerText(
        height,
        bankText,
        colors.white,
        colors.black
    )


    -- =====================================================
    -- WARNING MESSAGE
    -- =====================================================

    if
        warningText
        and os.clock()
            < warningUntil
    then

        centerText(
            2,
            warningText,
            warningColor,
            colors.black
        )

    else

        warningText = nil

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
-- RUN DISPLAY + AUDIO
-- =========================================================

parallel.waitForAny(
    displayLoop,
    audioLoop
)
