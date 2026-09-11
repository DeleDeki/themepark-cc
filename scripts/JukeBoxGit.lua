local dfpwm = require("cc.audio.dfpwm")

local OWNER = "DeleDeki"
local REPO = "themepark-cc"
local MUSIC_FOLDER = "music"

local TEMP_FILE = "/jukebox_temp.dfpwm"

local speaker = peripheral.find("speaker")

if not speaker then
    error("No speaker connected!")
end

local headers = {
    ["User-Agent"] = "CC-Tweaked-Jukebox",
    ["Accept"] = "application/vnd.github+json"
}

local apiURL =
    "https://api.github.com/repos/" ..
    OWNER .. "/" ..
    REPO .. "/contents/" ..
    MUSIC_FOLDER


-- =========================================================
-- DELETE TEMP FILE
-- =========================================================

local function cleanup()
    speaker.stop()

    if fs.exists(TEMP_FILE) then
        fs.delete(TEMP_FILE)
    end
end


-- =========================================================
-- GET SONG LIST FROM GITHUB
-- =========================================================

local function getSongs()

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

    -- GitHub error message
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


-- =========================================================
-- DOWNLOAD ONE SONG
-- =========================================================

local function downloadSong(song)

    -- Make absolutely sure old song is gone
    if fs.exists(TEMP_FILE) then
        fs.delete(TEMP_FILE)
    end

    print("")
    print("Downloading:")
    print(song.name)

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
        print("Download failed!")
        print(err or "Unknown error")
        return false
    end

    local file = fs.open(TEMP_FILE, "wb")

    if not file then
        response.close()
        print("Could not create temporary file.")
        return false
    end

    -- Download in small chunks.
    -- Never loads whole song into RAM.
    local success, downloadError = pcall(function()

        while true do

            local chunk = response.read(16 * 1024)

            if not chunk or #chunk == 0 then
                break
            end

            file.write(chunk)

        end

    end)

    response.close()
    file.close()

    if not success then

        if fs.exists(TEMP_FILE) then
            fs.delete(TEMP_FILE)
        end

        print("")
        print("Download failed:")
        print(downloadError)

        return false
    end

    return true
end


-- =========================================================
-- PLAY DOWNLOADED SONG
-- =========================================================

local function playSong(song)

    local file = fs.open(TEMP_FILE, "rb")

    if not file then
        print("Could not open song.")
        return
    end

    local decoder = dfpwm.make_decoder()

    term.clear()
    term.setCursorPos(1, 1)

    print("=== NOW PLAYING ===")
    print("")
    print(song.name:gsub("%.dfpwm$", ""))
    print("")
    print("Press Q to stop.")

    while true do

        -- Only 16 KB of compressed audio loaded at once
        local chunk = file.read(16 * 1024)

        if not chunk or #chunk == 0 then
            break
        end

        local buffer = decoder(chunk)

        while not speaker.playAudio(buffer) do

            local event, key = os.pullEvent()

            if event == "key" and key == keys.q then

                speaker.stop()
                file.close()

                return
            end

        end

        -- Allow old decoded buffer to be garbage collected
        buffer = nil
        chunk = nil
    end

    file.close()

    -- Wait for final audio chunk to finish
    os.pullEvent("speaker_audio_empty")
end


-- =========================================================
-- MAIN JUKEBOX
-- =========================================================

cleanup()

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

        print("No .dfpwm files found in:")
        print(MUSIC_FOLDER)

    else

        for i, song in ipairs(songs) do

            local displayName =
                song.name:gsub("%.dfpwm$", "")

            print(i .. ". " .. displayName)

        end

    end

    print("")
    print("R. Refresh song list")
    print("Q. Exit")
    print("")
    write("Choose song: ")

    local choice = read()

    -- EXIT
    if choice:lower() == "q" then

        cleanup()
        break

    -- REFRESH GITHUB LIST
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

            local song = songs[number]

            cleanup()

            if downloadSong(song) then

                playSong(song)

                -- DELETE SONG IMMEDIATELY AFTER PLAYING
                if fs.exists(TEMP_FILE) then
                    fs.delete(TEMP_FILE)
                end

            end

        else

            print("")
            print("Invalid song number.")
            sleep(1)

        end

    end

end
