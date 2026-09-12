-- =========================================================
-- SMALL PLANE COCKPIT DISPLAY
-- Aeronautics / Simulated + CC:Tweaked
-- =========================================================

-- ===== SETTINGS =====

-- If the nose of the plane was originally built pointing
-- NORTH/SOUTH, leave this as "z".
-- If it was built pointing EAST/WEST, change it to "x".
local FORWARD_AXIS = "z"

-- If bank moves the wrong way, change 1 to -1
local BANK_SIGN = 1

-- If the horizon moves UP when you pitch UP,
-- change this from 1 to -1.
local PITCH_SIGN = 1

-- How many degrees of pitch moves the horizon by one screen row.
local PITCH_DEGREES_PER_ROW = 10

-- ===== PERIPHERALS =====

local monitor = peripheral.wrap("top")
local gimbal = peripheral.wrap("left")
local altitudeSensor = peripheral.wrap("bottom")

if not monitor then
    error("No monitor on TOP")
end

if not gimbal then
    error("No gimbal sensor on LEFT")
end

if not altitudeSensor then
    error("No altitude sensor on BOTTOM")
end

-- Advanced monitor: maximum useful resolution on one block.
monitor.setTextScale(0.5)
monitor.setCursorBlink(false)

local width, height = monitor.getSize()

-- ===== HELPERS =====

local function round(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    else
        return math.ceil(n - 0.5)
    end
end

local function centerText(y, text, textColor, backgroundColor)
    local x = math.floor((width - #text) / 2) + 1

    monitor.setCursorPos(x, y)
    monitor.setTextColor(textColor)
    monitor.setBackgroundColor(backgroundColor)
    monitor.write(text)
end

local function clearRow(y, bg)
    monitor.setCursorPos(1, y)
    monitor.setBackgroundColor(bg)
    monitor.write(string.rep(" ", width))
end

-- ===== ARTIFICIAL HORIZON =====

local function drawHorizon(bank, pitch)
    -- Rows reserved for horizon:
    -- row 1 = altitude/thrust
    -- last row = bank angle
    local top = 2
    local bottom = height - 1

    local centerX = (width + 1) / 2
    local centerY = (top + bottom) / 2

    -- Prevent tan() going insane near 90 degrees.
    local visualBank = math.max(-80, math.min(80, bank))

    -- Horizon rotates opposite the aircraft.
    -- 0.5 compensates somewhat for tall monitor characters.
    local slope = math.tan(math.rad(-visualBank)) * 0.5

    -- Nose up -> horizon moves downward.
    local pitchOffset = pitch / PITCH_DEGREES_PER_ROW

    for y = top, bottom do
        local chars = {}
        local textCols = {}
        local bgCols = {}

        for x = 1, width do
            local horizonY =
                centerY
                + pitchOffset
                + slope * (x - centerX)

            local bg

            if y < horizonY then
                bg = colors.lightBlue -- sky
            else
                bg = colors.brown     -- ground
            end

            -- Draw the actual horizon boundary.
            if math.abs(y - horizonY) < 0.45 then
                chars[x] = "-"
                textCols[x] = colors.toBlit(colors.white)
            else
                chars[x] = " "
                textCols[x] = colors.toBlit(colors.white)
            end

            bgCols[x] = colors.toBlit(bg)
        end

        monitor.setCursorPos(1, y)
        monitor.blit(
            table.concat(chars),
            table.concat(textCols),
            table.concat(bgCols)
        )
    end

    -- Fixed aircraft symbol
    local aircraftY = round(centerY)

    local marker = "--+--"
    local markerX = math.floor((width - #marker) / 2) + 1

    monitor.setCursorPos(markerX, aircraftY)
    monitor.setTextColor(colors.yellow)
    monitor.write(marker)
end

-- ===== MAIN DISPLAY =====

local function drawDisplay()
    -- ALTITUDE
    local altitude = altitudeSensor.getHeight()

    -- GIMBAL
    local angles = gimbal.getAngles()

    local xAngle = angles[1]
    local zAngle = angles[2]

    local bank
    local pitch

    if FORWARD_AXIS == "z" then
        -- Plane built facing north/south
        pitch = xAngle
        bank = zAngle
    else
        -- Plane built facing east/west
        bank = xAngle
        pitch = zAngle
    end

    bank = bank * BANK_SIGN
    pitch = pitch * PITCH_SIGN

    -- THRUST / THROTTLE
    local thrust = redstone.getAnalogInput("right")

    -- Artificial horizon first
    drawHorizon(bank, pitch)

    -- =============================
    -- TOP INFORMATION BAR
    -- =============================

    clearRow(1, colors.black)

    local altText = "ALT " .. tostring(round(altitude))
    local thrustText = "THR " .. tostring(thrust)

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)

    monitor.setCursorPos(1, 1)
    monitor.write(altText)

    monitor.setCursorPos(width - #thrustText + 1, 1)
    monitor.write(thrustText)

    -- =============================
    -- BANK ANGLE BAR
    -- =============================

    clearRow(height, colors.black)

    local bankText = string.format(
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

-- ===== MAIN LOOP =====

monitor.clear()

while true do
    drawDisplay()

    -- 20 updates per second
    sleep(0.05)
end
