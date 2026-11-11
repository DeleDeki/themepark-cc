-- A local DFPWM file or a public GitHub RAW URL:
local SOURCE = "https://github.com/DeleDeki/themepark-cc/raw/refs/heads/main/music/themeParkMusic/CoasterLongCut.mp3"
-- For local playback, replace the line above with: local SOURCE = "song.dfpwm"
local VOLUME = 3 -- 0 to 3

local dfpwm = require("cc.audio.dfpwm")
local speakers = { peripheral.find("speaker") }
assert(#speakers > 0, "No speakers found. Connect and enable their wired modems.")
print("Playing on " .. #speakers .. " speaker(s).")

local handle, reason
if SOURCE:match("^https?://") then
    assert(http, "HTTP must be enabled to stream music.")
    handle, reason = http.get(SOURCE, nil, true)
else
    handle, reason = fs.open(SOURCE, "rb")
end
assert(handle, reason or ("Cannot open " .. SOURCE))

local ok, err = pcall(function()
    local decode = dfpwm.make_decoder()
    while true do
        local chunk = handle.read(16 * 1024)
        if not chunk or #chunk == 0 then break end
        local samples = decode(chunk)
        -- Each speaker accepts this chunk exactly once. Retry only those
        -- whose buffers are full, so one busy speaker cannot repeat audio
        -- on the others.
        local accepted = {}
        local remaining = #speakers
        while remaining > 0 do
            for i, speaker in ipairs(speakers) do
                if not accepted[i] and speaker.playAudio(samples, VOLUME) then
                    accepted[i] = true
                    remaining = remaining - 1
                end
            end
            if remaining > 0 then
                os.pullEvent("speaker_audio_empty")
            end
        end
    end
end)

handle.close()
if not ok then
    for _, speaker in ipairs(speakers) do
        pcall(speaker.stop)
    end
    error(err, 0)
end
