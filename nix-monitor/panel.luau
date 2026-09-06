-- Helper functions

function tr(key, fallback: string?)
	local translated = noctalia.tr(key)
	if translated == nil or translated == "" or translated == key then
		return fallback or key
	end
	return translated
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

local function shellQuote(value)
	return "'" .. string.gsub(value, "'", "'\"'\"'") .. "'"
end

local packagesExpanded = false
local packageScope = "system"
local panelOpen = false

local function getBackgroundColor()
	local color = cfg("panel_card_color")
	local opacity = cfg("panel_card_opacity") / 100
	return `{color}/{opacity}`
end

local function labelBox(subtext, text, glyph)
	return ui.column({
		fill = getBackgroundColor(),
		flexGrow = 1,
		height = 72,
		radius = 8,
		align = "center",
		padding = 8,
		justify = "space_between",
	}, {
		ui.glyph({
			name = glyph,
			size = 24,
		}),
		ui.label({
			text = text,
			fontWeight = "bold",
		}),
		ui.label({
			text = subtext,
			fontSize = 12,
			fontWeight = "medium",
		}),
	})
end

local function statLabel(text, glyph: string?)
	local items = {}
	if glyph ~= nil then
		table.insert(
			items,
			ui.glyph({
				name = glyph,
				size = 16,
			})
		)
	end

	table.insert(
		items,
		ui.label({
			text = text,
			fontSize = 12,
			fontWeight = "semibold",
		})
	)

	return ui.row({
		gap = 8,
		align = "center",
	}, items)
end

local function splitLines(value)
	local lines = {}
	if type(value) ~= "string" then
		return lines
	end

	for line in string.gmatch(value, "[^\r\n]+") do
		table.insert(lines, line)
	end

	return lines
end

local function pendingPackages(scope)
	local packages = {}
	for _, line in ipairs(splitLines(getState("packageComparison"))) do
		local category, name, current, newest = string.match(line, "^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
		-- Only existing packages with a changed version: additions/removals
		-- are not package updates and must not inflate the summary.
		if category == scope and current ~= newest and current ~= "—" and newest ~= "—" then
			table.insert(packages, { name = name, current = current, newest = newest })
		end
	end
	return packages
end

local function pendingCount(scope)
	local status = getState("packageComparisonStatus")
	if status == "ready" then return tostring(#pendingPackages(scope)) end
	if status == "loading" or status == "idle" then return "•••" end
	return "—"
end

local function appendPackageSection(items, details, keyPrefix)
	local status = getState("packageComparisonStatus")
	if status ~= "ready" then
		local message = "Version comparison unavailable; configure a flake update without a custom command."
		if status == "loading" or status == "idle" then
			message = "Comparing locked and updated packages…"
		elseif status == "error" then
			message = "Could not evaluate package versions. Retry on the next update check."
		end
		table.insert(items, ui.label({ text = message, fontSize = 11, maxWidth = 350 }))
		return
	end
	local packages = pendingPackages(keyPrefix)
	if #packages == 0 then
		table.insert(
			items,
			ui.label({
				text = tr("panel.no_package_updates", "No package updates"),
				fontSize = 11,
				color = "on_surface_variant",
			})
		)
		return
	end

	for index, package in ipairs(packages) do
		local name, version = package.name, package.current
		local rowProps = {
			key = `{keyPrefix}-{index}`,
			gap = 8,
			align = "center",
			paddingV = 2,
			paddingH = 8,
			onClick = "onPackagesSummaryClicked",
		}
		if index % 2 == 0 then
			rowProps.fill = "surface_variant/0.35"
			rowProps.radius = 4
		end

		table.insert(
			items,
			ui.row(rowProps, {
				ui.label({
					text = name,
					fontSize = 11,
					flexGrow = 1,
					maxLines = 1,
				}),
				ui.label({
					text = version,
					width = 90,
					maxWidth = 90,
					fontSize = 11,
					color = "on_surface_variant",
					textAlign = "end",
					maxLines = 1,
				}),
				ui.label({
					text = package.newest,
					width = 90,
					maxWidth = 90,
					fontSize = 11,
					color = package.newest ~= version and "primary" or "on_surface_variant",
					textAlign = "end",
					maxLines = 1,
				}),
			})
		)
	end
end

local function packageDetails()
	local items = {
		ui.row({
			gap = 8,
			align = "center",
			paddingH = 8,
		}, {
			ui.label({
				text = tr("panel.package"),
				fontSize = 11,
				fontWeight = "semibold",
				flexGrow = 1,
			}),
			ui.label({
				text = tr("panel.current", "Current"),
				width = 90,
				fontSize = 11,
				fontWeight = "semibold",
				textAlign = "end",
			}),
			ui.label({
				text = tr("panel.newest", "Newest"),
				width = 90,
				fontSize = 11,
				fontWeight = "semibold",
				textAlign = "end",
			}),
		}),
	}

	local system = packageScope == "system"
	appendPackageSection(
		items,
		getState(system and "systemPackageDetails" or "userPackageDetails"),
		packageScope
	)

	return items
end

local function packageSummary()
	local status = getState("packageComparisonStatus")
	local hasPackageUpdates = #pendingPackages("system") > 0 or #pendingPackages("user") > 0
	if status == "ready" and not hasPackageUpdates then
		return nil
	end

	return ui.row({
		fill = getBackgroundColor(),
		align = "center",
		justify = "space_between",
		gap = 12,
		paddingV = 8,
		paddingH = 12,
		radius = 8,
		onClick = "onPackagesSummaryClicked",
	}, {
		statLabel(`{tr("panel.system")}: {pendingCount("system")}`, "packages"),
		statLabel(`{tr("panel.user")}: {pendingCount("user")}`, "user"),
		ui.label({
			text = tr("panel.check_details", "Check details"),
			fontSize = 12,
			fontWeight = "semibold",
			color = "primary",
		}),
	})
end

local function renderPackageDetails()
	panel.render(ui.column({
		gap = 6,
	}, {
		ui.row({
			justify = "space_between",
			align = "center",
		}, {
			ui.label({
				text = tr("panel.title"),
				fontSize = 16,
			}),
			ui.label({
				text = getState("sourceLabel") or cfg("branch"),
				fontSize = 12,
			}),
		}),
		ui.button({
			text = tr("panel.back_to_overview"),
			glyph = "arrow-left",
			variant = "ghost",
			height = 28,
			fontSize = 12,
			onClick = "onPackagesSummaryClicked",
		}),
		ui.row({
			gap = 8,
		}, {
			ui.button({
				text = `{tr("panel.system_packages")}: {pendingCount("system")}`,
				variant = packageScope == "system" and "primary" or "outline",
				flexGrow = 1,
				height = 28,
				fontSize = 12,
				onClick = "onSystemPackagesClicked",
			}),
			ui.button({
				text = `{tr("panel.user_packages")}: {pendingCount("user")}`,
				variant = packageScope == "user" and "primary" or "outline",
				flexGrow = 1,
				height = 28,
				fontSize = 12,
				onClick = "onUserPackagesClicked",
			}),
		}),
		-- Flex allocates an exact height to the viewport before it measures
		-- its content. A height on ui.scroll alone only sets min/max bounds.
		ui.column({
			height = 180,
			align = "stretch",
		}, {
			ui.scroll({
				key = "packages-" .. packageScope,
				flexGrow = 1,
				fill = getBackgroundColor(),
				align = "stretch",
				gap = 4,
				padding = 8,
				radius = 8,
			}, packageDetails()),
		}),
	}))
end

local function render()
	local buttons = {}

	if getState("isRemoteCheckRunning") then
		table.insert(
			buttons,
			ui.button({
				text = tr("panel.cancel"),
				glyph = "cancel",
				flexGrow = 1,
				variant = "destructive",
				onClick = "onCancelClicked",
			})
		)
	else
		if getState("isUpdateAvailable") and not cfg("hide_update_button") then
			table.insert(
				buttons,
				ui.button({
					text = tr("panel.update"),
					glyph = "progress-down",
					flexGrow = 1,
					variant = "primary",
					onClick = "onUpdateClicked",
				})
			)
		else
			table.insert(
				buttons,
				ui.button({
					text = tr("panel.check"),
					glyph = "search",
					flexGrow = 1,
					variant = "outline",
					onClick = "onCheckClicked",
				})
			)
		end
	end

	if not cfg("hide_optimize_button") then
		table.insert(
			buttons,
			ui.button({
				text = tr("panel.optimize"),
				glyph = "database-cog",
				flexGrow = 1,
				variant = "primary",
				onClick = "onOptimizeClicked",
			})
		)
	end

	if not cfg("hide_clean_button") then
		table.insert(
			buttons,
			ui.button({
				text = tr("panel.clean"),
				glyph = "trash",
				flexGrow = 1,
				variant = "destructive",
				onClick = "onCleanClicked",
			})
		)
	end

	local lastCheckTimeStr = getState("lastRemoteCheckTimeStr")
	local generationItems = {
		statLabel(`SYS: {getState("nixosGenerations")}`, "device-desktop"),
		statLabel(`{tr("panel.current")}: {getState("nixosCurrentGen")}`, "device-desktop-check"),
	}

	if getState("hasHomeManager") and getState("hmGenerations") ~= "" and getState("hmCurrentGen") ~= "" then
		table.insert(generationItems, statLabel(`HM: {getState("hmGenerations")}`, "home"))

		table.insert(generationItems, statLabel(`{tr("panel.current")}: {getState("hmCurrentGen")}`, "home-check"))
	end

	if packagesExpanded then
		renderPackageDetails()
		return
	end

	panel.render(ui.column({
		gap = 6,
	}, {
		ui.row({
			justify = "space_between",
			align = "center",
		}, {
			ui.label({
				text = tr("panel.title"),
				fontSize = 16,
			}),

			ui.label({
				text = getState("sourceLabel") or cfg("branch"),
				fontSize = 12,
			}),
		}),
		ui.separator({
			thickness = 2,
			orientation = "horizontal",
			spacing = 2,
		}),
		ui.row({
			gap = 8,
			align = "center",
			justify = "space_between",
		}, {
			labelBox(tr("panel.local"), getState("localHash"), "devices-pc"),
			labelBox(tr("panel.remote"), getState("remoteHash"), "world"),
		}),
		ui.separator({
			thickness = 2,
			orientation = "horizontal",
			spacing = 2,
		}),
		ui.row({
			fill = getBackgroundColor(),
			align = "center",
			justify = "space_between",
			flexGrow = 1,
			paddingV = 4,
			paddingH = 8,
			radius = 8,
		}, generationItems),
		ui.row({
			fill = getBackgroundColor(),
			align = "center",
			justify = "center",
			flexGrow = 1,
			paddingV = 4,
			paddingH = 8,
			radius = 8,
		}, {
			statLabel(`{tr("panel.store_size")}: {getState("storeSize")}`, "database"),
			ui.spacer({ width = 16 }),
			statLabel(`{tr("panel.closure_size")}: {getState("closureSize")}`, "server"),
		}),
		ui.column({
			gap = 12,
		}, {
			ui.label({
				text = `{tr("panel.last_checked")}: {lastCheckTimeStr}`,
				fontSize = 12,
			}),
			ui.row({
				gap = 12,
				align = "center",
			}, buttons),
			packageSummary(),
		}),
	}))
end

local function renderIfOpen()
	if panelOpen then
		render()
	end
end

-- State watcher
watchState("isRemoteCheckRunning", renderIfOpen)
watchState("lastRemoteCheckTimeStr", renderIfOpen)
watchState("localHash", renderIfOpen)
watchState("remoteHash", renderIfOpen)
watchState("storeSize", renderIfOpen)
watchState("closureSize", renderIfOpen)
watchState("systemPackages", renderIfOpen)
watchState("userPackages", renderIfOpen)
watchState("systemPackageDetails", renderIfOpen)
watchState("userPackageDetails", renderIfOpen)
watchState("packageComparisonStatus", renderIfOpen)
watchState("packageComparison", renderIfOpen)
watchState("sourceLabel", renderIfOpen)

-- Hooks
function onOpen(_ctx)
	panelOpen = true
	packagesExpanded = false
	render()
end

function onClose()
	panelOpen = false
end

function update()
	renderIfOpen()
end

-- Click handler
function onCheckClicked()
	setState("command", "check")
end

function onCancelClicked()
	setState("command", "cancel")
end

function onPackagesSummaryClicked()
	packagesExpanded = not packagesExpanded
	render()
end

function onSystemPackagesClicked()
	packageScope = "system"
	render()
end

function onUserPackagesClicked()
	packageScope = "user"
	render()
end

function onUpdateClicked()
	local command = cfg("update_command")
	if command == "" then
		local flakePath = noctalia.string.trim(cfg("flake_path") or "")
		local flakeInput = noctalia.string.trim(cfg("flake_input") or "")
		local nixosConfiguration = noctalia.string.trim(cfg("nixos_configuration") or "")

		if flakePath ~= "" and flakeInput ~= "" and nixosConfiguration ~= "" then
			local flakeTarget = "path:" .. flakePath .. "#" .. nixosConfiguration
			command = "cd "
				.. shellQuote(flakePath)
				.. " && nix flake update "
				.. shellQuote(flakeInput)
				.. " && sudo nixos-rebuild switch --flake "
				.. shellQuote(flakeTarget)
		end
	end

	if command == "" then
		noctalia.notifyError(tr("notification.update_configuration_incomplete"))
		return
	end
	runCommandInTerminal(command)
end

function onCleanClicked()
	local command = cfg("clean_command")
	if command == "" then
		noctalia.notifyError(tr("notification.clean_command_is_empty"))
		return
	end
	runCommandInTerminal(command)
end

function onOptimizeClicked()
	local command = cfg("optimize_command")
	if command == "" then
		noctalia.notifyError(tr("notification.optimize_command_is_empty"))
		return
	end
	runCommandInTerminal(command)
end

function runCommandInTerminal(command)
	if cfg("close_on_enter") then
		command = `{command} && echo && read -p "{tr("terminal.press_enter_to_exit")}"`
	end

	command = `{command} || (echo && read -p "{tr("terminal.command_exits_non_zero")}")`
	panel.close()
	noctalia.runInTerminal(command)
end
