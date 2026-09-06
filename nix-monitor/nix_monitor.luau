function tr(key)
	return noctalia.tr(key)
end

function cfg(key)
	return noctalia.getConfig(key)
end

function getState(key)
	return noctalia.state.get(key)
end

function watchState(key, cb)
	noctalia.state.watch(key, cb)
end

function displayWidget(glyph: string, text: string, color: string?)
	local _color = color or "on_surface"

	if cfg("colorize_text") then
		barWidget.setColor(_color)
	end

	if cfg("colorize_glyph") then
		barWidget.setGlyphColor(_color)
	end

	if cfg("show_glyph") then
		barWidget.setGlyph(glyph)
	end

	if cfg("show_text") then
		barWidget.setText(text)
	end
end

local function refreshWidget()
	if getState("isRemoteCheckRunning") or getState("packageComparisonStatus") == "loading" then
		displayWidget(cfg("checking_glyph"), tr("bar.checking"), cfg("checking_color"))
	else
		if getState("isUpdateAvailable") then
			displayWidget(cfg("update_available_glyph"), tr("bar.update_available"), cfg("update_available_color"))
		else
			if getState("localHash") == "n/a" or getState("remoteHash") == "n/a" then
				displayWidget(cfg("unknown_glyph"), tr("bar.unknown"), cfg("unknown_color"))
			else
				displayWidget(cfg("up_to_date_glyph"), tr("bar.up_to_date"), cfg("up_to_date_color"))
			end
		end
	end
end

-- Refresh immediately when the displayed status changes. Keeping the timer as
-- a low-frequency fallback avoids a constant stream of update callbacks around
-- the same time as a completed status check and keeps clicks responsive.
watchState("isRemoteCheckRunning", refreshWidget)
watchState("packageComparisonStatus", refreshWidget)
watchState("isUpdateAvailable", refreshWidget)
watchState("localHash", refreshWidget)
watchState("remoteHash", refreshWidget)
noctalia.setUpdateInterval(5000)

-- Hooks
function update()
	refreshWidget()
end

function onClick()
	noctalia.togglePanel("luisrocha/nix-monitor:panel")
end
