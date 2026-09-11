local dfpwm = require("cc.audio.dfpwm")

local speaker = peripheral.find("speaker")

if not speaker then
    error("No speaker connected!")
end

local function getSongs()
    local songs = {}

    for _, file in ipairs(fs.list("/")) do
        if file:lower():match("%.dfpwm$") then
            table.insert(songs, file)
        end
    end

    table.sort(songs)
    return songs
end

local function playSong(file)
    local decoder = dfpwm.make_decoder()
    local handle = fs.open("/" .. file, "rb")

    if not handle then
        print("Could not open " .. file)
        return
    end

    term.clear()
    term.setCursorPos(1, 1)

    print("Now playing:")
    print(file:gsub("%.dfpwm$", ""))
    print("")
    print("Press Q to stop.")

    while true do
        local chunk = handle.read(16 * 1024)

        if not chunk then
            break
        end

        local buffer = decoder(chunk)

        while not speaker.playAudio(buffer) do
            local event, key = os.pullEvent()

            if event == "key" and key == keys.q then
                speaker.stop()
                handle.close()
                return
            end
        end
    end

    handle.close()

    -- Wait until final audio finishes
    os.pullEvent("speaker_audio_empty")
end

while true do
    term.clear()
    term.setCursorPos(1, 1)

    local songs = getSongs()

    print("=== JUKEBOX ===")
    print("")

    if #songs == 0 then
        print("No .dfpwm songs found.")
        print("")
        print("Put songs directly on this computer.")
        return
    end

    for i, song in ipairs(songs) do
        local name = song:gsub("%.dfpwm$", "")
        print(i .. ". " .. name)
    end

    print("")
    print("Q. Exit")
    print("")
    write("Choose song: ")

    local choice = read()

    if choice:lower() == "q" then
        break
    end

    local number = tonumber(choice)

    if number and songs[number] then
        playSong(songs[number])
    else
        print("Invalid song number.")
        sleep(1)
    end
end
