-- =========================================================
-- SMALL PLANE COCKPIT DISPLAY V1
-- Create Aeronautics / Simulated + CC:Tweaked
--
-- Displays:
--   Altitude
--   Artificial horizon
--   Bank angle
--   Thrust 0-15
-- =========================================================


-- =========================
-- SETTINGS
-- =========================

-- Gimbal returns:
-- angles[1] = X angle
-- angles[2] = Z angle
--
-- If BANK reacts when you PITCH instead of when you ROLL,
-- change this from 1 to 2.
local BANK_AXIS = 1

-- Pitch will automatically use the other axis.
local PITCH_AXIS = 2

-- If bank direction is backwards, change 1 to -1.
local BANK_SIGN = 1

-- If horizon moves the wrong direction while pitching,
-- change 1 to -1.
local PITCH_SIGN = 1

-- Bigger number = horizon moves less for pitch.
local PITCH_DEGREES_PER_ROW = 10


-- =========================
-- FIND PERIPHERALS
-- =========================

local monitor = peripheral.find("monitor")
local gimbal = peripheral.find("gimbal_sensor")
local altitudeSensor = peripheral.find("altitude_sensor")

if not monitor then
    error("No monitor found")
end

if not gimbal then
    error("No gimbal sensor found")
end

if not altitudeSensor then
    error("No altitude sensor found")
end


-- =========================
-- MONITOR SETUP
-- =========================

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)

local width, height = monitor.getSize()


-- =========================
-- HELPERS
-- =========================

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
    monitor.write(string.rep(" ", width))
end


local function centerText(y, text, textColor, background)
    local x = math.floor((width - #text) / 2) + 1

    monitor.setBackgroundColor(background)
    monitor.setTextColor(textColor)
    monitor.setCursorPos(x, y)
    monitor.write(text)
end


-- =========================
-- THRUST
-- =========================

-- We don't care which side the Redstone Link actually is.
-- Read all six sides and use the strongest analog signal.
--
-- Your monitor may pass a weak 0/1 signal,
-- but the actual Redstone Link should give the real 0-15.

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
        local value = redstone.getAnalogInput(side)

        if value > strongest then
            strongest = value
        end
    end

    return strongest
end


-- =========================
-- ARTIFICIAL HORIZON
-- =========================

local function drawHorizon(bank, pitch)

    -- First row reserved for ALT / THR.
    -- Last row reserved for BANK.
    local top = 2
    local bottom = height - 1

    local centerX = (width + 1) / 2
    local centerY = (top + bottom) / 2

    -- Prevent tan() becoming insane near 90 degrees.
    local visualBank = math.max(-80, math.min(80, bank))

    -- Horizon rotates opposite to aircraft bank.
    -- 0.5 compensates for monitor character proportions.
    local slope = math.tan(math.rad(-visualBank)) * 0.5

    -- Nose up/down moves horizon vertically.
    local pitchOffset =
        pitch / PITCH_DEGREES_PER_ROW

    for y = top, bottom do

        local chars = {}
        local foreground = {}
        local background = {}

        for x = 1, width do

            local horizonY =
                centerY
                + pitchOffset
                + slope * (x - centerX)

            -- SKY
            if y < horizonY then
                background[x] =
                    colors.toBlit(colors.lightBlue)

            -- GROUND
            else
                background[x] =
                    colors.toBlit(colors.brown)
            end

            -- Horizon line
            if math.abs(y - horizonY) < 0.45 then
                chars[x] = "-"
                foreground[x] =
                    colors.toBlit(colors.white)
            else
                chars[x] = " "
                foreground[x] =
                    colors.toBlit(colors.white)
            end
        end

        monitor.setCursorPos(1, y)

        monitor.blit(
            table.concat(chars),
            table.concat(foreground),
            table.concat(background)
        )
    end


    -- =========================
    -- AIRCRAFT SYMBOL
    -- =========================

    local aircraftY = round(centerY)

    local marker = "--+--"

    local markerX =
        math.floor((width - #marker) / 2) + 1

    monitor.setCursorPos(markerX, aircraftY)
    monitor.setTextColor(colors.yellow)
    monitor.setBackgroundColor(colors.black)
    monitor.write(marker)
end


-- =========================
-- MAIN DISPLAY
-- =========================

local function drawDisplay()

    -- -------------------------
    -- ALTITUDE
    -- -------------------------

    local altitude =
        altitudeSensor.getHeight()


    -- -------------------------
    -- GIMBAL
    -- -------------------------

    local angles =
        gimbal.getAngles()

    local bank =
        angles[BANK_AXIS] * BANK_SIGN

    local pitch =
        angles[PITCH_AXIS] * PITCH_SIGN


    -- -------------------------
    -- THRUST
    -- -------------------------

    local thrust =
        getThrust()


    -- -------------------------
    -- DRAW HORIZON
    -- -------------------------

    drawHorizon(bank, pitch)


    -- =========================
    -- TOP BAR
    -- =========================

    clearRow(1, colors.black)

    local altitudeText =
        "ALT " .. tostring(round(altitude))

    local thrustText =
        "THR " .. tostring(thrust)

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)

    monitor.setCursorPos(1, 1)
    monitor.write(altitudeText)

    monitor.setCursorPos(
        width - #thrustText + 1,
        1
    )

    monitor.write(thrustText)


    -- =========================
    -- BOTTOM BANK DISPLAY
    -- =========================

    clearRow(height, colors.black)

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
end


-- =========================
-- MAIN LOOP
-- =========================

monitor.setBackgroundColor(colors.black)
monitor.clear()

while true do

    drawDisplay()

    -- 20 updates per second
    sleep(0.05)

end
