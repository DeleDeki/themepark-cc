while true do
    os.pullEvent("redstone")

    if redstone.getInput("back") then
        shell.run("music")
    end
end
