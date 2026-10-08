-- youtube.lua
-- CC:Tweaked Advanced Monitor YouTube streaming client.
--
-- Usage:
--   youtube <ws://or-wss://host:port>
-- Example:
--   youtube wss://your-public-domain.example
--
-- The helper server asks yt-dlp/ffmpeg to decode the YouTube video.
-- This computer only receives CC-ready 16-colour frames and 48 kHz PCM audio.

local args = {...}
local SERVER = args[1]

if not SERVER or SERVER == "" then
    write("WebSocket server URL: ")
    SERVER = read()
end

if not SERVER:match("^wss?://") then
    error("URL must start with ws:// or wss://", 0)
end

local monitor = peripheral.find("monitor")
if not monitor then
    error("No monitor connected.", 0)
end
if not monitor.isColor() then
    error("An Advanced Monitor is required.", 0)
end

local speaker = peripheral.find("speaker")

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()

local W, H = monitor.getSize()

term.clear()
term.setCursorPos(1, 1)
print("CC YouTube Player")
print("Monitor: " .. W .. "x" .. H .. " @ text scale 0.5")
print("Speaker: " .. (speaker and "yes" or "no"))
print("")
write("YouTube URL: ")
local youtubeURL = read()

if youtubeURL == "" then
    error("No YouTube URL entered.", 0)
end

print("")
print("Connecting to:")
print(SERVER)

local ws, err = http.websocket(SERVER)
if not ws then
    print("")
    printError("WebSocket connection failed:")
    printError(tostring(err))
    print("")
    print("If it says Domain not permitted, the")
    print("server's CC:Tweaked HTTP rules block it.")
    return
end

print("Connected. Starting stream...")

ws.send(textutils.serializeJSON({
    type = "play",
    url = youtubeURL,
    width = W,
    height = H,
    audio = speaker ~= nil
}))

local BLIT = "0123456789abcdef"
local spaces = string.rep(" ", W)
local white = string.rep("0", W)

local function drawFrame(data)
    -- Packet layout:
    -- byte 1 = ASCII V
    -- following bytes = palette indexes 0..15, one byte per monitor cell.
    if #data < 1 + W * H then return end

    local p = 2
    for y = 1, H do
        local bg = {}
        for x = 1, W do
            local idx = data:byte(p) or 15
            idx = math.max(0, math.min(15, idx))
            bg[x] = BLIT:sub(idx + 1, idx + 1)
            p = p + 1
        end
        monitor.setCursorPos(1, y)
        monitor.blit(spaces, white, table.concat(bg))
    end
end

local function playAudio(data)
    if not speaker or #data <= 1 then return end

    local samples = {}
    for i = 2, #data do
        local b = data:byte(i)
        if b >= 128 then b = b - 256 end
        samples[#samples + 1] = b
    end

    while not speaker.playAudio(samples) do
        os.pullEvent("speaker_audio_empty")
    end
end

local function showStatus(message)
    term.setCursorPos(1, 7)
    term.clearLine()
    write(message)
end

local ok, runtimeErr = pcall(function()
    while true do
        local message, binaryOrReason = ws.receive()

        if message == nil then
            error("WebSocket closed: " .. tostring(binaryOrReason or "unknown reason"))
        end

        local isBinary = binaryOrReason == true

        if isBinary then
            local packetType = message:sub(1, 1)
            if packetType == "V" then
                drawFrame(message)
            elseif packetType == "A" then
                playAudio(message)
            end
        else
            local obj = textutils.unserializeJSON(message)
            if obj and obj.type == "status" then
                showStatus(obj.message or "")
            elseif obj and obj.type == "error" then
                error(obj.message or "Server error")
            elseif obj and obj.type == "end" then
                showStatus("Playback finished.")
                break
            end
        end
    end
end)

pcall(function() ws.close() end)

if not ok then
    print("")
    printError(tostring(runtimeErr))
end
