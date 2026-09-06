noctalia.setUpdateInterval(1000)

-- Helper functions
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

function killWithPidFile(file)
	if noctalia.fileExists(file) then
		local content = noctalia.readFile(file) or ""
		local pid = noctalia.string.trim(content)

		if type(pid) == "string" and pid ~= "" then
			noctalia.runAsync(`pkill -9 -P {pid} && kill -9 {pid}`)
		end
		noctalia.removeFile(file)
	end
end

local function nixString(value)
	value = string.gsub(value, "\\", "\\\\")
	value = string.gsub(value, '"', '\\"')
	return '"' .. value .. '"'
end

-- Vars
local branch = cfg("branch")
local flakePath = noctalia.string.trim(cfg("flake_path") or "")
local flakeInput = noctalia.string.trim(cfg("flake_input") or "nixpkgs")
local updateCheckInterval = cfg("update_check_interval")
local updateCheckDurationThreshold = cfg("update_check_duration_threshold")
local generationsCheckInterval = cfg("generation_check_interval")
local systemStatsCheckInterval = cfg("system_stats_check_interval")
local systemStatsCheckDurationThreshold = cfg("system_stats_check_duration_threshold")
local stateDir = noctalia.pluginDataDir() or "/tmp/nix-monitor"
local remoteHashFile = stateDir .. "/remoteHash"
local storeSizeFile = stateDir .. "/storeSize"
local closureSizeFile = stateDir .. "/closureSize"
local systemPackagesFile = stateDir .. "/systemPackages"
local userPackagesFile = stateDir .. "/userPackages"
local remotePidFile = stateDir .. "/remoteHash.pid"
local storePidFile = stateDir .. "/storeSize.pid"
local closurePidFile = stateDir .. "/closureSize.pid"
local systemPackagesPidFile = stateDir .. "/systemPackages.pid"
local userPackagesPidFile = stateDir .. "/userPackages.pid"
local packagesFinishedMarker = "__NIX_MONITOR_PACKAGES_DONE__"
local showUpdateAvailableNotification = true

local localHashCmd = "nixos-version --hash 2> /dev/null | cut -c 1-7"
local remoteHashCmd = "git ls-remote https://github.com/NixOS/nixpkgs " .. branch .. " 2>/dev/null | cut -c 1-7"
local sourceLabel = branch
local sourceLabelCmd = nil
local comparisonFile = stateDir .. "/packageComparison"
local comparisonErrorFile = stateDir .. "/packageComparison.log"
local comparisonPidFile = stateDir .. "/packageComparison.pid"
local comparisonStarted = 0
local comparisonRunning = false
local function shellQuote(value)
	return "'" .. string.gsub(value, "'", "'\"'\"'") .. "'"
end

function checkPackageComparison()
	if comparisonRunning then return end
	local configuration = noctalia.string.trim(cfg("nixos_configuration") or "")
	if flakePath == "" or flakeInput == "" or configuration == "" or (cfg("update_command") or "") ~= "" then
		setState("packageComparisonStatus", "unavailable")
		return
	end
	setState("packageComparisonStatus", "loading")
	setState("packageComparison", "")
	noctalia.writeFile(comparisonFile, "")
	noctalia.writeFile(comparisonErrorFile, "")
	local command = "sh " .. shellQuote(noctalia.pluginDir() .. "/compare-packages.sh")
		.. " " .. shellQuote(flakePath) .. " " .. shellQuote(flakeInput)
		.. " " .. shellQuote(configuration) .. " " .. shellQuote(noctalia.getenv("USER") or "")
		.. " " .. shellQuote(noctalia.pluginDir())
	comparisonStarted = os.time()
	comparisonRunning = true
	local started = noctalia.runAsync("(" .. command .. "; result=$?; echo; echo __RESULT_$result) > "
		.. shellQuote(comparisonFile) .. " 2> " .. shellQuote(comparisonErrorFile)
		.. " & echo $! > " .. shellQuote(comparisonPidFile))
	if not started then
		comparisonRunning = false
		setState("packageComparisonStatus", "error")
	end
end

if flakePath ~= "" and flakeInput ~= "" then
	local flakeRef = "path:" .. flakePath
	local lockPath = flakePath .. "/flake.lock"
	local inputName = nixString(flakeInput)
	local localExpr = "(builtins.getFlake "
		.. nixString(flakeRef)
		.. ").inputs."
		.. inputName
		.. ".shortRev"
	local remoteExpr = "let lock = builtins.fromJSON (builtins.readFile "
		.. nixString(lockPath)
		.. "); inputNode = lock.nodes.${lock.root}.inputs."
		.. inputName
		.. "; node = lock.nodes.${inputNode}; original = node.original; ref = original.ref or \"HEAD\"; source = if original.type == \"github\" then \"github:${original.owner}/${original.repo}/${ref}\" else throw \"nix-monitor flake input must use a GitHub source\"; in (builtins.getFlake source).shortRev"
	local sourceLabelExpr = "let lock = builtins.fromJSON (builtins.readFile "
		.. nixString(lockPath)
		.. "); inputNode = lock.nodes.${lock.root}.inputs."
		.. inputName
		.. "; original = lock.nodes.${inputNode}.original; in original.ref or original.repo or "
		.. inputName

	localHashCmd = "nix eval --raw --impure --expr '" .. localExpr .. "' 2> /dev/null | cut -c 1-7"
	remoteHashCmd = "nix eval --raw --impure --expr '" .. remoteExpr .. "' 2> /dev/null | cut -c 1-7"
	sourceLabelCmd = "nix eval --raw --impure --expr '" .. sourceLabelExpr .. "' 2> /dev/null"
	sourceLabel = flakeInput
end
local nixosGenerationsCmd = "nixos-rebuild list-generations | tail -n +2 | wc -l"
local nixosCurrentGenCmd = "nixos-rebuild list-generations | grep True | awk '{print $1}'"
local hmGenerationsCmd = "home-manager generations | wc -l"
local hmCurrentGenCmd = "home-manager generations | grep '(current)' | awk '{print $5}'"
local storeSizeCmd = "du -s --block-size=1 /nix/store | awk '{printf \"%.2f GiB\", $1/1073741824}'"
local closureSizeCmd = "nix path-info --closure-size --human-readable /run/current-system | awk '{print $2, $3}'"
local systemPackagesCmd = "(nix-store -q --references /run/current-system/sw 2>/dev/null || true; echo "
	.. packagesFinishedMarker
	.. ")"
local userPackagesCmd = "(nix-store -q --references ~/.nix-profile 2>/dev/null || true; echo "
	.. packagesFinishedMarker
	.. ")"

-- State inits
setState("lastLocalCheckTime", os.time())
setState("lastRemoteCheckRunTime", os.time())
setState("lastRemoteCheckTime", os.time())
setState("lastRemoteCheckTimeStr", "n/a")
setState("localHash", "n/a")
setState("remoteHash", "n/a")
setState("isRemoteCheckRunning", false)
setState("isUpdateAvailable", false)
setState("lastGenerationsCheckTime", 0)
setState("isSystemStatsCheckRunning", false)
setState("systemStatsCheckHasBeenPerformed", false)
setState("lastSystemStatsCheckTime", os.time())
setState("lastSystemStatsCheckRunTime", os.time())
setState("hasHomeManager", noctalia.commandExists("home-manager"))
setState("nixosGenerations", "•••")
setState("nixosCurrentGen", "•••")
setState("hmGenerations", "•••")
setState("hmCurrentGen", "•••")
setState("storeSize", "•••")
setState("closureSize", "•••")
setState("systemPackages", "•••")
setState("userPackages", "•••")
setState("systemPackageDetails", "")
setState("userPackageDetails", "")
setState("sourceLabel", sourceLabel)

if sourceLabelCmd ~= nil then
	noctalia.runAsync(sourceLabelCmd, function(result)
		local resolvedSourceLabel = noctalia.string.trim(result.stdout)
		if result.exitCode == 0 and resolvedSourceLabel ~= "" then
			setState("sourceLabel", resolvedSourceLabel)
		end
	end)
end
setState("packageComparisonStatus", "idle")
setState("packageComparison", "")

noctalia.mkdirAll(stateDir)
noctalia.writeFile(remoteHashFile, "")

-- Local check
function checkLocalHash()
	setState("lastLocalCheckTime", os.time())
	noctalia.runAsync(localHashCmd, function(res)
		if res.exitCode == 0 then
			setState("localHash", noctalia.string.trim(res.stdout))
		end
	end)
end

-- Remote check
--
-- Currently it is writing to a file because when I use the runAsync with
-- the callback, it is timed out
function checkRemoteHash(delay: number?)
	local _delay = delay or 0

	if getState("isRemoteCheckRunning") then
		return
	end

	setState("isRemoteCheckRunning", true)
	setState("lastRemoteCheckRunTime", os.time())
	-- Refresh package data with startup, scheduled, and manual update checks.
	checkPackageComparison()

	if cfg("show_update_check_notification") then
		noctalia.notify(tr("notification.checking_update"))
	end

	noctalia.writeFile(remoteHashFile, "")
	noctalia.runAsync(`sleep {_delay} && {remoteHashCmd} > {remoteHashFile} & echo $! > {remotePidFile}`)
end

-- Check if the remoteHash check command is finished by reading the file
function checkRemoteStatus()
	local remoteHashFileContent = noctalia.readFile(remoteHashFile) or ""
	local remoteHash = noctalia.string.trim(remoteHashFileContent)

	if type(remoteHash) == "string" and remoteHash ~= "" then
		setState("isRemoteCheckRunning", false)
		setState("remoteHash", remoteHash)
		onRemoteHashCheckCompleted()
	end
end

function onRemoteHashCheckCompleted()
	if cfg("show_update_check_notification") then
		noctalia.notify(tr("notification.update_check_completed"))
	end

	setState("lastRemoteCheckTime", os.time())

	local date = noctalia.formatTime("%Y-%m-%d %H:%M:%S")
	setState("lastRemoteCheckTimeStr", date)

	noctalia.removeFile(remotePidFile)
end

function cancelRemoteCheck()
	setState("isRemoteCheckRunning", false)
	killWithPidFile(remotePidFile)
end

-- Generation check
function checkGenerations()
	setState("lastGenerationsCheckTime", os.time())

	noctalia.runAsync(nixosGenerationsCmd, function(result)
		setState("nixosGenerations", noctalia.string.trim(result.stdout))
	end)

	noctalia.runAsync(nixosCurrentGenCmd, function(result)
		setState("nixosCurrentGen", noctalia.string.trim(result.stdout))
	end)

	if getState("hasHomeManager") then
		noctalia.runAsync(hmGenerationsCmd, function(result)
			setState("hmGenerations", noctalia.string.trim(result.stdout))
		end)

		noctalia.runAsync(hmCurrentGenCmd, function(result)
			setState("hmCurrentGen", noctalia.string.trim(result.stdout))
		end)
	end
end

-- System stats check
function checkSystemStats(force)
	if getState("isSystemStatsCheckRunning") then
		return
	end

	if cfg("system_stats_check_mode") == "off" then
		return
	end

	if cfg("system_stats_check_mode") == "on_start" and getState("systemStatsCheckHasBeenPerformed") and not force then
		return
	end

	setState("storeSize", "•••")
	setState("closureSize", "•••")
	setState("systemPackages", "•••")
	setState("userPackages", "•••")
	setState("systemPackageDetails", "")
	setState("userPackageDetails", "")
	setState("systemStatsCheckHasBeenPerformed", true)
	setState("isSystemStatsCheckRunning", true)
	setState("lastSystemStatsCheckRunTime", os.time())

	noctalia.writeFile(storeSizeFile, "")
	noctalia.writeFile(closureSizeFile, "")
	noctalia.writeFile(systemPackagesFile, "")
	noctalia.writeFile(userPackagesFile, "")

	-- Sleep 0 to trigger noctalia calling /bin/sh
	noctalia.runAsync(`sleep 0 && {storeSizeCmd} > {storeSizeFile} & echo $! > {storePidFile}`)
	noctalia.runAsync(`sleep 0 && {closureSizeCmd} > {closureSizeFile} & echo $! > {closurePidFile}`)
	noctalia.runAsync(`sleep 0 && {systemPackagesCmd} > {systemPackagesFile} & echo $! > {systemPackagesPidFile}`)
	noctalia.runAsync(`sleep 0 && {userPackagesCmd} > {userPackagesFile} & echo $! > {userPackagesPidFile}`)
end

local function parsePackageDetails(content)
	local packages = {}

	for path in string.gmatch(content, "[^\r\n]+") do
		if path ~= packagesFinishedMarker then
			local package = string.match(path, "^/nix/store/[^-]+%-(.+)$") or path
			table.insert(packages, package)
		end
	end

	table.sort(packages)
	return tostring(#packages), table.concat(packages, "\n")
end

function checkSystemStatsFile()
	local storeSizeFileContent = noctalia.readFile(storeSizeFile) or ""
	local storeSize = noctalia.string.trim(storeSizeFileContent)
	local closureSizeFileContent = noctalia.readFile(closureSizeFile) or ""
	local closureSize = noctalia.string.trim(closureSizeFileContent)
	local systemPackagesFileContent = noctalia.readFile(systemPackagesFile) or ""
	local userPackagesFileContent = noctalia.readFile(userPackagesFile) or ""
	local systemPackagesFinished = string.find(systemPackagesFileContent, packagesFinishedMarker, 1, true) ~= nil
	local userPackagesFinished = string.find(userPackagesFileContent, packagesFinishedMarker, 1, true) ~= nil

	if typeof(storeSize) == "string" and storeSize ~= "" then
		setState("storeSize", storeSize)
	end

	if typeof(closureSize) == "string" and closureSize ~= "" then
		setState("closureSize", closureSize)
	end

	if systemPackagesFinished then
		local count, details = parsePackageDetails(systemPackagesFileContent)
		setState("systemPackages", count)
		setState("systemPackageDetails", details)
	end

	if userPackagesFinished then
		local count, details = parsePackageDetails(userPackagesFileContent)
		setState("userPackages", count)
		setState("userPackageDetails", details)
	end

	local success = typeof(storeSize) == "string"
		and storeSize ~= ""
		and typeof(closureSize) == "string"
		and closureSize ~= ""
		and systemPackagesFinished
		and userPackagesFinished

	if success then
		setState("isSystemStatsCheckRunning", false)
		setState("lastSystemStatsCheckTime", os.time())
		noctalia.removeFile(storePidFile)
		noctalia.removeFile(closurePidFile)
		noctalia.removeFile(systemPackagesPidFile)
		noctalia.removeFile(userPackagesPidFile)
	end
end

function cancelSystemCheck()
	setState("isSystemStatsCheckRunning", false)
	killWithPidFile(storePidFile)
	killWithPidFile(closurePidFile)
	killWithPidFile(systemPackagesPidFile)
	killWithPidFile(userPackagesPidFile)
end

-- Init
checkLocalHash()
checkRemoteHash(10)
if cfg("system_stats_check_mode") ~= "off" then
	checkSystemStats()
else
	setState("storeSize", "n/a")
	setState("closureSize", "n/a")
	setState("systemPackages", "n/a")
	setState("userPackages", "n/a")
end

-- Command watcher
watchState("command", function(command)
	if command == "check" then
		checkLocalHash()
		cancelRemoteCheck()
		checkRemoteHash()
		checkGenerations()
		checkSystemStats(true)
	end

	if command == "cancel" then
		cancelRemoteCheck()
		cancelSystemCheck()
	end
end)

--
-- Hooks
--

function update()
	if comparisonRunning then
		local result = noctalia.readFile(comparisonFile) or ""
		local status = string.match(result, "__RESULT_(%d+)%s*$")
		if status then
			comparisonRunning = false
			setState("packageComparison", string.gsub(result, "\n__RESULT_%d+%s*$", ""))
			setState("packageComparisonStatus", status == "0" and "ready" or "error")
			noctalia.removeFile(comparisonPidFile)
		elseif os.time() - comparisonStarted > 60 * updateCheckDurationThreshold then
			killWithPidFile(comparisonPidFile)
			comparisonRunning = false
			setState("packageComparisonStatus", "error")
		end
	end
	-- Check local hash every 10 seconds
	if os.time() - getState("lastLocalCheckTime") >= 10 then
		checkLocalHash()
	end

	-- Remote check
	if (os.time() - getState("lastRemoteCheckTime")) >= 60 * updateCheckInterval then
		checkRemoteHash()
	end

	if getState("isRemoteCheckRunning") then
		checkRemoteStatus()

		-- Remote check timeout
		if (os.time() - getState("lastRemoteCheckRunTime")) >= 60 * updateCheckDurationThreshold then
			cancelRemoteCheck()
		end
	end

	if
		getState("localHash") ~= getState("remoteHash")
		and getState("localHash") ~= "n/a"
		and getState("remoteHash") ~= "n/a"
	then
		setState("isUpdateAvailable", true)

		if cfg("show_update_available_notification") and showUpdateAvailableNotification then
			noctalia.notify(tr("notification.update_is_available"))
			showUpdateAvailableNotification = false
		end
	else
		setState("isUpdateAvailable", false)
		showUpdateAvailableNotification = true
	end

	-- Generations check
	if (os.time() - getState("lastGenerationsCheckTime")) >= 60 * generationsCheckInterval then
		checkGenerations()
	end

	-- System stats check
	if (os.time() - getState("lastSystemStatsCheckTime")) >= 60 * systemStatsCheckInterval then
		checkSystemStats()
	end

	if getState("isSystemStatsCheckRunning") then
		checkSystemStatsFile()

		-- System stats check timeout
		if (os.time() - getState("lastSystemStatsCheckRunTime")) >= 60 * systemStatsCheckDurationThreshold then
			cancelSystemCheck()
		end
	end
end

function onExit(signal)
	killWithPidFile(comparisonPidFile)
	cancelRemoteCheck()
	cancelSystemCheck()
end
