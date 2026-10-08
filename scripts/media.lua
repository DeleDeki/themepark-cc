-- media.lua
-- CC:Tweaked monitor + speaker media player client.
--
-- Usage:
--   media ws://127.0.0.1:8765
--
-- Then paste:
-- - YouTube URL
-- - direct .mp4/.webm/etc URL
-- - local helper path (only meaningful to helper PC)

local args = {...}
local SERVER = args[1]

if not SERVER or SERVER == "" then
    write("WebSocket server URL: ")
    SERVER = read()
end

if not SERVER:match("^wss?://") then
    error("Server URL must start with ws:// or wss://", 0)
end

local monitor = peripheral.find("monitor")
if not monitor then error("No monitor connected.", 0) end
if not monitor.isColor() then error("Advanced Monitor required.", 0) end

local speaker = peripheral.find("speaker")

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()

local W, H = monitor.getSize()

term.clear()
term.setCursorPos(1,1)
print("CC Media Player")
print("Monitor: " .. W .. "x" .. H)
print("Speaker: " .. (speaker and "yes" or "no"))
print("")
write("Media URL/path: ")
local mediaURL = read()

if mediaURL == "" then
    error("No media URL/path entered.", 0)
end

print("")
print("Connecting...")

local ws, err = http.websocket(SERVER)
if not ws then
    printError("WebSocket failed: " .. tostring(err))
    return
end

print("Connected.")

ws.send(textutils.serializeJSON({
    type = "play",
    url = mediaURL,
    width = W,
    height = H,
    audio = speaker ~= nil
}))

local BLIT = "0123456789abcdef"
local spaces = string.rep(" ", W)
local white = string.rep("0", W)

local function drawFrame(data)
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

local audioQueue = {}

local function pushAudio(data)
    if not speaker or #data <= 1 then return end

    local samples = {}
    for i = 2, #data do
        local b = data:byte(i)
        if b >= 128 then b = b - 256 end
        samples[#samples + 1] = b
    end

    audioQueue[#audioQueue + 1] = samples
end

local function pumpAudio()
    if not speaker then return end

    while #audioQueue > 0 do
        local samples = audioQueue[1]

        if speaker.playAudio(samples) then
            table.remove(audioQueue, 1)
        else
            break
        end
    end
end

local function status(msg)
    term.setCursorPos(1, 7)
    term.clearLine()
    write(tostring(msg))
end

local ok, runtimeErr = pcall(function()
    while true do
        pumpAudio()

        local event, a, b, c = os.pullEvent()

        if event == "websocket_message" then
            local url, message, binary = a, b, c

            if url == SERVER then
                if binary then
                    local packetType = message:sub(1,1)

                    if packetType == "V" then
                        drawFrame(message)
                    elseif packetType == "A" then
                        pushAudio(message)
                        pumpAudio()
                    end
                else
                    local obj = textutils.unserializeJSON(message)

                    if obj then
                        if obj.type == "status" then
                            status(obj.message or "")
                        elseif obj.type == "error" then
                            error(obj.message or "Server error")
                        elseif obj.type == "end" then
                            status("Playback finished.")
                            break
                        end
                    end
                end
            end

        elseif event == "speaker_audio_empty" then
            pumpAudio()

        elseif event == "websocket_closed" then
            local url = a
            if url == SERVER then
                error("WebSocket closed.")
            end

        elseif event == "websocket_failure" then
            local url, reason = a, b
            if url == SERVER then
                error("WebSocket failure: " .. tostring(reason))
            end
        end
    end
end)

pcall(function() ws.close() end)

if not ok then
    print("")
    printError(tostring(runtimeErr))
end
