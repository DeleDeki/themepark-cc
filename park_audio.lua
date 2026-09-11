
local dfpwm = require("cc.audio.dfpwm")

local FILE = "AerospinCUT.dfpwm"
local VOLUME = 3
local LOOP = true

local speakers = { peripheral.find("speaker") }

if #speakers == 0 then
    error("No speakers found!")
end

if not fs.exists(FILE) then
    error("Audio file not found: " .. FILE)
end

print("=== PARK AUDIO SYSTEM ===")
print("Track: " .. FILE)
print("Speakers: " .. #speakers)
print("Volume: " .. VOLUME)
print("")
print("Ctrl+T to stop")

local function playOnAll(buffer)
    local waiting = {}

    for i = 1, #speakers do
        waiting[i] = true
    end

    while true do
        local remaining = 0

        for i, speaker in ipairs(speakers) do
            if waiting[i] then
                if speaker.playAudio(buffer, VOLUME) then
                    waiting[i] = false
                else
                    remaining = remaining + 1
                end
            end
        end

        if remaining == 0 then
            return
        end

        os.pullEvent("speaker_audio_empty")
    end
end

local function playSong()
    local decoder = dfpwm.make_decoder()

    for chunk in io.lines(FILE, 16 * 1024) do
        local buffer = decoder(chunk)
        playOnAll(buffer)
    end
end

repeat
    playSong()
until not LOOP