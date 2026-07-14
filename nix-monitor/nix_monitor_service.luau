noctalia.setUpdateInterval(1000)

function tr(key)
    return noctalia.tr(key)
end

function cfg(key)
    return noctalia.getConfig(key)
end

function getState(key)
    return noctalia.state.get(key)
end

function setState(key, val)
    noctalia.state.set(key, val)
end

function watchState(key, cb)
    noctalia.state.watch(key, cb)
end

local branch = cfg("branch")
local updateCheckInterval = cfg("check_interval")
local checkDurationThreshold = cfg("check_duration_threshold")
local systemStatsCheckInterval = cfg("system_stats_check_interval")
local isInit = true
local stateDir = "/tmp/nix-monitor"
local localHashFile = stateDir .. "/localHash"
local remoteHashFile = stateDir .. "/remoteHash"
local storeSizeFile = stateDir .. "/storeSize"
local closureSizeFile = stateDir .. "/closureSize"

local localHashCmd  = "nixos-version --hash 2> /dev/null | cut -c -7 > " .. localHashFile .. " &"
local remoteHashCmd = "sleep 5 && git ls-remote https://github.com/NixOS/nixpkgs " .. branch .. " 2>/dev/null | cut -c 1-7 > " .. remoteHashFile .. " &"
local nixosGenerationsCmd = "nixos-rebuild list-generations | tail -n +2 | wc -l"
local nixosCurrentGenCmd = "nixos-rebuild list-generations | grep True | awk '{print $1}'"
local hmGenerationsCmd = "home-manager generations | wc -l"
local hmCurrentGenCmd = "home-manager generations | grep '(current)' | awk '{print $5}'"
local storeSizeCmd = `du -s --block-size=1GiB /nix/store | awk '\{print $1 " GiB"\}' > {storeSizeFile} &`
local closureSizeCmd = `nix path-info --closure-size --human-readable /run/current-system | awk '\{print $2, $3\}' > {closureSizeFile} &`

setState("lastRunTime", os.time())
setState("lastCheckTime", os.time())
setState("lastCheckTimeStr", "n/a")
setState("localHash", "n/a")
setState("remoteHash", "n/a")
setState("isRunning", false)
setState("isUpdateAvailable", false)
setState("lastGenerationsCheckTime", 0)
setState("lastSystemStatsCheckTime", 0)
setState("hasHomeManager", noctalia.commandExists("home-manager"))
setState("nixosGenerations", "•••")
setState("nixosCurrentGen", "•••")
setState("hmGenerations", "•••")
setState("hmCurrentGen", "•••")
setState("storeSize", "•••")
setState("closureSize", "•••")

noctalia.mkdirAll(stateDir)
noctalia.writeFile(localHashFile, "")
noctalia.writeFile(remoteHashFile, "")

function update()
    if isInit or (os.time() - getState("lastCheckTime")) >= 60 * updateCheckInterval then
        isInit = false
        cancelCheck()
        checkUpdate()
    end

    if getState("isRunning") then
        if isCheckUpdateSuccessfully() then
            onHashCheckCompleted()
        end
    end

    if getState("isSystemStatsCheckRunning") then
        checkSystemStatsFile()
    end

    if getState("isRunning") and (os.time() - getState("lastRunTime")) >= 60 * checkDurationThreshold then
        cancelCheck()
    end

    if (os.time() - getState("lastGenerationsCheckTime")) >= 20 then
        checkGenerations()
    end

    if (os.time() - getState("lastSystemStatsCheckTime")) >= 60 * systemStatsCheckInterval then
        checkSystemStats()
    end
end

function checkUpdate()
    if getState("isRunning") then
        return
    end

    setState("lastRunTime", os.time())

    if cfg("show_checking_notification") then
        noctalia.notify(tr("notification.checking_update"))
    end

    setState("isRunning", true)

    noctalia.writeFile(localHashFile, "")
    noctalia.writeFile(remoteHashFile, "")

    noctalia.runAsync(localHashCmd)
    noctalia.runAsync(remoteHashCmd)
end

function isCheckUpdateSuccessfully()
    local localHash = noctalia.string.trim(noctalia.readFile(localHashFile))
    local remoteHash = noctalia.string.trim(noctalia.readFile(remoteHashFile))

    if typeof(localHash) == "string" and localHash ~= "" then
        setState("localHash", localHash)
    end

    if typeof(remoteHash) == "string" and remoteHash ~= "" then
        setState("remoteHash", remoteHash)
    end

    local success = typeof(localHash) == "string" and localHash ~= "" and
        typeof(remoteHash) == "string" and remoteHash ~= ""

    if success then
        onHashCheckCompleted()
    end

    return success
end

function onHashCheckCompleted()
    if getState("localHash") ~= getState("remoteHash") then
        setState("isUpdateAvailable", true)
        if cfg("show_update_notification") then
            noctalia.notify(tr("notification.update_is_available"))
        end
    end

    if cfg("show_checking_notification") then
        noctalia.notify(tr("notification.update_check_completed"))
    end

    setState("lastCheckTime", os.time())
    noctalia.runAsync("date '+%Y-%m-%d %H:%M'", function(date) setState("lastCheckTimeStr", date.stdout) end)

    setState("isRunning", false)
end

function cancelCheck()
    setState("isRunning", false)
    noctalia.runAsync(`kill $(ps -ef | grep "git ls-remote https://github.com/NixOS/nixpkgs" | grep -v grep | awk '\{print $2\}')`)
end

watchState("command", function(command)
    if command == "check" then
        checkUpdate()
    end

    if command == "cancel" then
        cancelCheck()
    end
end)

function checkGenerations()
    setState("lastGenerationsCheckTime", os.time())

    noctalia.runAsync(nixosGenerationsCmd, function(result)
        setState("nixosGenerations", result.stdout)
    end)

    noctalia.runAsync(nixosCurrentGenCmd, function(result)
        setState("nixosCurrentGen", result.stdout)
    end)

    if getState("hasHomeManager") then
        noctalia.runAsync(hmGenerationsCmd, function(result)
            setState("hmGenerations", result.stdout)
        end)

        noctalia.runAsync(hmCurrentGenCmd, function(result)
            setState("hmCurrentGen", result.stdout)
        end)
    end
end

function checkSystemStats()
    if getState("isSystemStatsCheckRunning") then
        return
    end

    setState("isSystemStatsCheckRunning", true)
    setState("lastSystemStatsCheckTime", os.time())

    noctalia.runAsync(storeSizeCmd)
    noctalia.runAsync(closureSizeCmd)
end

function checkSystemStatsFile()
    local storeSize = noctalia.string.trim(noctalia.readFile(storeSizeFile))
    local closureSize = noctalia.string.trim(noctalia.readFile(closureSizeFile))

    if typeof(storeSize) == "string" and storeSize ~= "" then
        setState("storeSize", storeSize)
    end

    if typeof(closureSize) == "string" and closureSize ~= "" then
        setState("closureSize", closureSize)
    end

    local success = typeof(storeSize) == "string" and storeSize ~= "" and
        typeof(closureSize) == "string" and closureSize ~= ""

    if success then
        setState("isSystemStatsCheckRunning", false)
    end
end

function onExit(signal)
    cancelCheck()
end
