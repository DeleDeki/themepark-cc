local dfpwm = require("cc.audio.dfpwm")

local OWNER = "DeleDeki"
local REPO = "themepark-cc"
local MUSIC_FOLDER = "music"

local speaker = peripheral.find("speaker")

if not speaker then
    error("No speaker connected!")
end

local apiURL =
    "https://api.github.com/repos/" ..
    OWNER .. "/" ..
    REPO .. "/contents/" ..
    MUSIC_FOLDER

local headers = {
    ["User-Agent"] = "CC-Tweaked-Jukebox",
    ["Accept"] = "application/vnd.github+json"
}


-- =============================================
-- GET SONG LIST FROM GITHUB
-- =============================================

local function getSongs()

    term.clear()
    term.setCursorPos(1, 1)

    print("Loading songs from GitHub...")

    local response, err = http.get({
        url = apiURL,
        headers = headers
    })

    if not response then
        return nil, err or "Could not connect to GitHub"
    end

    local body = response.readAll()
    response.close()

    local data = textutils.unserializeJSON(body)

    body = nil

    if not data then
        return nil, "Could not read GitHub response"
    end

    if data.message then
        return nil, data.message
    end

    local songs = {}

    for _, item in ipairs(data) do

        if item.type == "file"
        and item.name:lower():match("%.dfpwm$")
        and item.download_url then

            table.insert(songs, {
                name = item.name,
                url = item.download_url
            })

        end
    end

    table.sort(songs, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    return songs
end


-- =============================================
-- STREAM SONG DIRECTLY FROM GITHUB
-- =============================================

local function playSong(song)

    speaker.stop()

    term.clear()
    term.setCursorPos(1, 1)

    print("Connecting to GitHub...")
    print(song.name:gsub("%.dfpwm$", ""))

    local response, err = http.get({
        url = song.url,
        headers = {
            ["User-Agent"] = "CC-Tweaked-Jukebox"
        },
        binary = true,
        timeout = 30
    })

    if not response then
        print("")
        print("Could not open song:")
        print(err or "Unknown error")
        print("")
        print("Press any key.")
        os.pullEvent("key")
        return
    end

    local decoder = dfpwm.make_decoder()

    term.clear()
    term.setCursorPos(1, 1)

    print("=== NOW PLAYING ===")
    print("")
    print(song.name:gsub("%.dfpwm$", ""))
    print("")
    print("Streaming from GitHub")
    print("")
    print("Press Q to stop.")

    while true do

        -- Only read 16 KB from GitHub at a time.
        -- Nothing is saved to the computer.
        local chunk = response.read(16 * 1024)

        if not chunk or #chunk == 0 then
            break
        end

        local buffer = decoder(chunk)

        while not speaker.playAudio(buffer) do

            local event, key = os.pullEvent()

            if event == "key" and key == keys.q then

                speaker.stop()
                response.close()

                return
            end

        end

        chunk = nil
        buffer = nil
    end

    response.close()

    -- Let final audio buffer finish playing
    os.pullEvent("speaker_audio_empty")
end


-- =============================================
-- MAIN JUKEBOX
-- =============================================

local songs, errorMessage = getSongs()

if not songs then
    print("")
    print("Could not load songs:")
    print(errorMessage)
    return
end


while true do

    term.clear()
    term.setCursorPos(1, 1)

    print("=== THEME PARK JUKEBOX ===")
    print("")

    if #songs == 0 then

        print("No .dfpwm songs found.")

    else

        for i, song in ipairs(songs) do

            local name =
                song.name:gsub("%.dfpwm$", "")

            print(i .. ". " .. name)

        end

    end

    print("")
    print("R. Refresh songs")
    print("Q. Exit")
    print("")
    write("Choose song: ")

    local choice = read()

    if choice:lower() == "q" then

        speaker.stop()
        break

    elseif choice:lower() == "r" then

        local newSongs, err = getSongs()

        if newSongs then
            songs = newSongs
        else
            print("")
            print("Refresh failed:")
            print(err)
            sleep(2)
        end

    else

        local number = tonumber(choice)

        if number and songs[number] then

            playSong(songs[number])

        else

            print("")
            print("Invalid song number.")
            sleep(1)

        end

    end

end
