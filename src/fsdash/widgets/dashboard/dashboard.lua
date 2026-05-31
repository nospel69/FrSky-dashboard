--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local fsdash = require("FSDash")

local dashboard = {}

local supportedResolutions = {
    {784, 294}, {784, 316}, {800, 458}, {800, 480},
    {472, 191}, {472, 210}, {480, 301}, {480, 320},
    {630, 236}, {630, 258}, {640, 338}, {640, 360}
}

local DEFAULT_THEME = "system/default"
local themesBasePath = "SCRIPTS:/" .. fsdash.config.baseDir .. "/widgets/dashboard/themes/"
local themesUserPath = "SCRIPTS:/" .. fsdash.config.preferences .. "/dashboard/"
local preferencesBasePath = "SCRIPTS:/" .. fsdash.config.preferences
local themeFallbackLogDir = "SCRIPTS:/" .. fsdash.config.preferences .. "/logs"
local themeFallbackLogFile = themeFallbackLogDir .. "/theme-fallback.log"

local currentState = nil
local loadedStates = {}
local lastSizeKey = nil
local themeStateSignature = nil
local nextThemeStateCheck = 0
local themeStateCheckInterval = 0.25
local unsupportedResolution = false
local forceFullRepaint = true
local lastInvalidateAt = 0
local invalidateInterval = 0.1
local lastHiddenWakeAt = 0
local hiddenWakeInterval = 1.0
local gestureActive = false
local gestureStartX = 0
local gestureStartY = 0
local gestureTriggered = false
local gestureConsumeUntilTouchEnd = false
local GESTURE_MIN_DY = 20
local GESTURE_MAX_DX = 40
local TOOLBAR_TIMEOUT = 5.0

dashboard.title = false
dashboard.renders = dashboard.renders or {}
dashboard.objectsByType = {}
dashboard.boxRects = {}
dashboard._moduleCache = dashboard._moduleCache or {}
dashboard.toolbarVisible = false
dashboard.selectedToolbarIndex = nil
dashboard.toolbarLastActivityAt = 0
dashboard.selectedBoxIndex = nil
dashboard.currentWidgetPath = nil
dashboard.DEFAULT_THEME = DEFAULT_THEME
dashboard.themeFallbackUsed = {preflight = false, inflight = false, postflight = false}
dashboard.themeFallbackTime = {preflight = 0, inflight = 0, postflight = 0}
dashboard.themeFallbackReason = {preflight = nil, inflight = nil, postflight = nil}
dashboard.themeFallbackLoggedSignature = {preflight = nil, inflight = nil, postflight = nil}
dashboard.themeDecisionLoggedSignature = {preflight = nil, inflight = nil, postflight = nil}
dashboard.themeActiveStateSignature = nil

local function appendThemeFallbackLog(state, themeValue, reason)
    local signature = tostring(state) .. "|" .. tostring(themeValue) .. "|" .. tostring(reason)
    if dashboard.themeFallbackLoggedSignature[state] == signature then
        return
    end

    dashboard.themeFallbackLoggedSignature[state] = signature
    os.mkdir(preferencesBasePath)
    os.mkdir(themeFallbackLogDir)

    local timestamp = os.date and os.date("%Y-%m-%d %H:%M:%S") or tostring(os.clock())
    local line = string.format("%s | state=%s | theme=%s | reason=%s", timestamp, tostring(state), tostring(themeValue), tostring(reason))
    local file = io.open(themeFallbackLogFile, "a")
    if file then
        io.write(file, line, "\n")
        io.close(file)
    end
end

local function appendThemeDebugLog(message)
    if not (fsdash and fsdash.getLogLevel and fsdash.getLogLevel() == "debug") then
        return
    end

    os.mkdir(preferencesBasePath)
    os.mkdir(themeFallbackLogDir)

    local timestamp = os.date and os.date("%Y-%m-%d %H:%M:%S") or tostring(os.clock())
    local line = string.format("%s | debug | %s", timestamp, tostring(message))
    local file = io.open(themeFallbackLogFile, "a")
    if file then
        io.write(file, line, "\n")
        io.close(file)
    end
end

function dashboard.touchToolbar()
    dashboard.toolbarLastActivityAt = os.clock()
end

function dashboard.openToolbar()
    dashboard.toolbarVisible = true
    dashboard.selectedToolbarIndex = dashboard.selectedToolbarIndex or 1
    dashboard.touchToolbar()
end

function dashboard.closeToolbar()
    dashboard.toolbarVisible = false
    dashboard.selectedToolbarIndex = nil
    dashboard.toolbarLastActivityAt = 0
end

local function ensureDashboardLibraries()
    dashboard.utils = dashboard.utils or assert(loadfile("SCRIPTS:/" .. fsdash.config.baseDir .. "/widgets/dashboard/lib/utils.lua"))()
    dashboard.loaders = dashboard.loaders or assert(loadfile("SCRIPTS:/" .. fsdash.config.baseDir .. "/widgets/dashboard/lib/loaders.lua"))()
    dashboard.toolbar = dashboard.toolbar or assert(loadfile("SCRIPTS:/" .. fsdash.config.baseDir .. "/widgets/dashboard/lib/toolbar.lua"))()
end

local function consumeTouchSequence(value)
    if not system.killEvents then
        return
    end

    if value ~= nil then
        system.killEvents(value)
    end

    if TOUCH_START then
        system.killEvents(TOUCH_START)
    end

    if value == TOUCH_END and TOUCH_END then
        system.killEvents(TOUCH_END)
    end
end

local function getThemeForState(state)
    local modelPrefs = fsdash.session.modelPreferences and fsdash.session.modelPreferences.dashboard or nil
    local userPrefs = fsdash.preferences and fsdash.preferences.dashboard or {}
    local modelValue = modelPrefs and modelPrefs["theme_" .. state] or nil
    local userValue = userPrefs["theme_" .. state]
    local rawModelValue = modelValue
    local rawUserValue = userValue
    local value = modelValue

    if value == "nil" then
        value = nil
    end

    if type(value) == "string" then
        value = value:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
    end

    if value == "Default" or value == "@Default" or value == "default" then
        value = "system/default"
    elseif value == "RT-RC" or value == "@RT-RC" or value == "rt-rc" or value == "@rt-rc" or value == "system/rt-rc" then
        value = "system/@rt-rc"
    end

    -- Treat model-level default aliases as "no override" so global selection can apply.
    if value == "system/default" then
        value = nil
    end

    if type(userValue) == "string" then
        userValue = userValue:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
        if userValue == "Default" or userValue == "@Default" or userValue == "default" then
            userValue = "system/default"
        elseif userValue == "RT-RC" or userValue == "@RT-RC" or userValue == "rt-rc" or userValue == "@rt-rc" or userValue == "system/rt-rc" then
            userValue = "system/@rt-rc"
        end
        if userValue ~= "" and not userValue:find("/", 1, true) then
            userValue = "system/" .. userValue
        end
    end

    if type(value) == "string" and value ~= "" and not value:find("/", 1, true) then
        value = "system/" .. value
    end

    local result = value or userValue or DEFAULT_THEME
    local source = value and "model" or (userValue and "global" or "default")
    local signature = string.format("rawModel=%s|rawUser=%s|model=%s|global=%s|result=%s|source=%s", tostring(rawModelValue), tostring(rawUserValue), tostring(value), tostring(userValue), tostring(result), source)
    if dashboard.themeDecisionLoggedSignature[state] ~= signature then
        dashboard.themeDecisionLoggedSignature[state] = signature
        appendThemeDebugLog(string.format("decision %s rawModel=%s rawGlobal=%s model=%s global=%s result=%s source=%s", tostring(state), tostring(rawModelValue), tostring(rawUserValue), tostring(value), tostring(userValue), tostring(result), source))
    end

    return result
end

local function resolveThemeFolder(basePath, folder)
    if type(folder) ~= "string" then
        return nil
    end

    local normalized = folder:gsub("^/+", ""):gsub("/+$", "")
    if normalized == "" then
        return nil
    end

    if fsdash.utils.dir_exists(basePath, normalized) then
        return normalized
    end

    local candidates = {normalized}
    if normalized:sub(1, 1) == "@" then
        candidates[#candidates + 1] = normalized:sub(2)
    else
        candidates[#candidates + 1] = "@" .. normalized
    end

    for _, candidate in ipairs(candidates) do
        if candidate ~= "" and fsdash.utils.dir_exists(basePath, candidate) then
            return candidate
        end
    end

    local folders = system.listFiles(basePath)
    if not folders then
        return nil
    end

    local lowerCandidates = {}
    for _, candidate in ipairs(candidates) do
        lowerCandidates[#lowerCandidates + 1] = string.lower(candidate)
    end

    for _, existing in ipairs(folders) do
        if existing ~= "." and existing ~= ".." and fsdash.utils.dir_exists(basePath, existing) then
            local lowerExisting = string.lower(existing)
            for _, lowerCandidate in ipairs(lowerCandidates) do
                if lowerExisting == lowerCandidate then
                    return existing
                end
            end
        end
    end

    return nil
end

local function loadStateScript(themeFolder, state, isFallback)
    isFallback = isFallback or false

    if type(themeFolder) == "string" then
        themeFolder = themeFolder:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
    end

    local sourceType, folder = nil, nil
    if type(themeFolder) == "string" then
        sourceType, folder = themeFolder:match("([^/]+)/(.+)")
    end

    if not sourceType or not folder then
        if not isFallback then
            dashboard.themeFallbackReason[state] = "invalid theme path: " .. tostring(themeFolder)
            appendThemeFallbackLog(state, themeFolder, dashboard.themeFallbackReason[state])
            return loadStateScript(DEFAULT_THEME, state, true)
        end

        dashboard.themeFallbackUsed[state] = true
        dashboard.themeFallbackTime[state] = os.clock()
        return nil
    end

    local basePath = sourceType == "user" and themesUserPath or themesBasePath
    local resolvedFolder = resolveThemeFolder(basePath, folder)
    if not resolvedFolder then
        if not isFallback then
            dashboard.themeFallbackReason[state] = "theme folder not found: " .. tostring(sourceType .. "/" .. tostring(folder))
            appendThemeFallbackLog(state, themeFolder, dashboard.themeFallbackReason[state])
            return loadStateScript(DEFAULT_THEME, state, true)
        end

        dashboard.themeFallbackUsed[state] = true
        dashboard.themeFallbackTime[state] = os.clock()
        return nil
    end

    local initPath = basePath .. resolvedFolder .. "/init.lua"
    local initLoader = loadfile(initPath)

    if not initLoader then
        if not isFallback then
            dashboard.themeFallbackReason[state] = "init.lua missing: " .. tostring(sourceType .. "/" .. resolvedFolder)
            appendThemeFallbackLog(state, themeFolder, dashboard.themeFallbackReason[state])
            return loadStateScript(DEFAULT_THEME, state, true)
        end

        dashboard.themeFallbackUsed[state] = true
        dashboard.themeFallbackTime[state] = os.clock()
        return nil
    end

    local okInit, initTable = pcall(initLoader)
    if not okInit or type(initTable) ~= "table" then
        if not isFallback then
            dashboard.themeFallbackReason[state] = "init.lua error: " .. tostring(initTable)
            appendThemeFallbackLog(state, themeFolder, dashboard.themeFallbackReason[state])
            return loadStateScript(DEFAULT_THEME, state, true)
        end

        dashboard.themeFallbackUsed[state] = true
        dashboard.themeFallbackTime[state] = os.clock()
        return nil
    end

    local scriptName = type(initTable[state]) == "string" and initTable[state] ~= "" and initTable[state] or (state .. ".lua")
    local scriptPath = basePath .. resolvedFolder .. "/" .. scriptName
    local loader = loadfile(scriptPath)

    if not loader then
        if not isFallback then
            dashboard.themeFallbackReason[state] = "state script missing: " .. tostring(sourceType .. "/" .. resolvedFolder .. "/" .. scriptName)
            appendThemeFallbackLog(state, themeFolder, dashboard.themeFallbackReason[state])
            return loadStateScript(DEFAULT_THEME, state, true)
        end

        dashboard.themeFallbackUsed[state] = true
        dashboard.themeFallbackTime[state] = os.clock()
        return nil
    end

    dashboard.themeFallbackUsed[state] = isFallback == true
    dashboard.themeFallbackTime[state] = isFallback and os.clock() or 0
    if not isFallback then
        dashboard.themeFallbackReason[state] = nil
        dashboard.themeFallbackLoggedSignature[state] = nil
    end

    if initTable.standalone then
        return loader
    end

    local okModule, module = pcall(loader)
    if not okModule then
        if not isFallback then
            dashboard.themeFallbackReason[state] = "state script error: " .. tostring(module)
            appendThemeFallbackLog(state, themeFolder, dashboard.themeFallbackReason[state])
            return loadStateScript(DEFAULT_THEME, state, true)
        end

        dashboard.themeFallbackUsed[state] = true
        dashboard.themeFallbackTime[state] = os.clock()
        return nil
    end

    if type(module) == "table" then
        module.__themeDebugPath = tostring(sourceType .. "/" .. resolvedFolder .. "/" .. scriptName)
        module.__themeDebugState = state
    end

    return module
end

local function loadObjectType(box)
    local objectType = box and box.type
    if not objectType then
        return
    end

    if dashboard._moduleCache[objectType] == nil then
        local objectPath = "SCRIPTS:/" .. fsdash.config.baseDir .. "/widgets/dashboard/objects/" .. objectType .. ".lua"
        local loader = loadfile(objectPath)
        if loader then
            local ok, module = pcall(loader)
            dashboard._moduleCache[objectType] = ok and module or false
        else
            dashboard._moduleCache[objectType] = false
        end
    end

    if dashboard._moduleCache[objectType] then
        dashboard.objectsByType[objectType] = dashboard._moduleCache[objectType]
    end
end

local function loadObjects(module)
    dashboard.objectsByType = {}

    local boxes = type(module.boxes) == "function" and module.boxes() or (module.boxes or {})
    local headerBoxes = module.header_boxes or {}

    for _, box in ipairs(boxes) do
        loadObjectType(box)
    end

    for _, box in ipairs(headerBoxes) do
        loadObjectType(box)
    end
end

local function reloadTheme()
    local selectedPreflight = getThemeForState("preflight")
    local selectedInflight = getThemeForState("inflight")
    local selectedPostflight = getThemeForState("postflight")

    themeStateSignature = dashboard.utils and dashboard.utils.getThemeSignature and dashboard.utils.getThemeSignature() or themeStateSignature
    nextThemeStateCheck = os.clock() + themeStateCheckInterval
    loadedStates = {
        preflight = loadStateScript(selectedPreflight, "preflight"),
        inflight = loadStateScript(selectedInflight, "inflight"),
        postflight = loadStateScript(selectedPostflight, "postflight")
    }

    appendThemeDebugLog(string.format("reload selected preflight=%s inflight=%s postflight=%s", tostring(selectedPreflight), tostring(selectedInflight), tostring(selectedPostflight)))
    appendThemeDebugLog(string.format("reload loaded preflight=%s inflight=%s postflight=%s", tostring(loadedStates.preflight ~= nil), tostring(loadedStates.inflight ~= nil), tostring(loadedStates.postflight ~= nil)))
    appendThemeDebugLog(string.format("reload module preflight=%s inflight=%s postflight=%s", tostring(loadedStates.preflight and loadedStates.preflight.__themeDebugPath), tostring(loadedStates.inflight and loadedStates.inflight.__themeDebugPath), tostring(loadedStates.postflight and loadedStates.postflight.__themeDebugPath)))
    appendThemeDebugLog(string.format("reload fallback preflight=%s inflight=%s postflight=%s", tostring(dashboard.themeFallbackUsed.preflight), tostring(dashboard.themeFallbackUsed.inflight), tostring(dashboard.themeFallbackUsed.postflight)))
    appendThemeDebugLog(string.format("reload reason preflight=%s inflight=%s postflight=%s", tostring(dashboard.themeFallbackReason.preflight), tostring(dashboard.themeFallbackReason.inflight), tostring(dashboard.themeFallbackReason.postflight)))

    dashboard.utils.resetImageCache()
    dashboard.boxRects = {}
    currentState = nil
    fsdash.theme.version = (fsdash.theme.version or 0) + 1
    forceFullRepaint = true
end

function dashboard.reload_themes()
    ensureDashboardLibraries()
    reloadTheme()
    if lcd.invalidate then
        lcd.invalidate()
    end
end

local function getBoxSize(box, boxWidth, boxHeight, padding, widgetW, widgetH)
    if box.w_pct and box.h_pct then
        local widthPct = box.w_pct > 1 and (box.w_pct / 100) or box.w_pct
        local heightPct = box.h_pct > 1 and (box.h_pct / 100) or box.h_pct
        return math.floor(widthPct * widgetW), math.floor(heightPct * widgetH)
    end

    if box.w and box.h then
        return tonumber(box.w) or boxWidth, tonumber(box.h) or boxHeight
    end

    if box.colspan or box.rowspan then
        local width = math.floor((box.colspan or 1) * boxWidth + ((box.colspan or 1) - 1) * padding)
        local height = math.floor((box.rowspan or 1) * boxHeight + ((box.rowspan or 1) - 1) * padding)
        return width, height
    end

    return boxWidth, boxHeight
end

local function getBoxPosition(box, width, height, boxWidth, boxHeight, padding, widgetW, widgetH)
    if box.x_pct and box.y_pct then
        local xPct = box.x_pct > 1 and (box.x_pct / 100) or box.x_pct
        local yPct = box.y_pct > 1 and (box.y_pct / 100) or box.y_pct
        return math.floor(xPct * (widgetW - width)), math.floor(yPct * (widgetH - height))
    end

    if box.x and box.y then
        return tonumber(box.x) or 0, tonumber(box.y) or 0
    end

    if box.col and box.row then
        local x = math.floor((box.col - 1) * (boxWidth + padding)) + (box.xOffset or 0)
        local y = math.floor(padding + (box.row - 1) * (boxHeight + padding))
        return x, y
    end

    return 0, 0
end

local function adjustDimension(dimension, cells, padCount, padding)
    return dimension - ((dimension - padCount * padding) % cells)
end

local function buildRects(module)
    local utils = dashboard.utils
    local layout = module.layout or {}
    local headerLayout = module.header_layout or {}
    local boxes = type(module.boxes) == "function" and module.boxes() or (module.boxes or {})
    local headerBoxes = module.header_boxes or {}

    local windowW, windowH = lcd.getWindowSize()
    local isFullScreen = utils.isFullScreen(windowW, windowH)

    local cols = layout.cols or 1
    local rows = layout.rows or 1
    local padding = layout.padding or 0

    local contentHeight = windowH
    if isFullScreen and headerLayout.height then
        contentHeight = contentHeight - headerLayout.height
    end

    local adjustedW = adjustDimension(windowW, cols, cols - 1, padding)
    local adjustedH = adjustDimension(contentHeight, rows, rows + 1, padding)
    local xOffset = math.floor((windowW - adjustedW) / 2)

    local contentW = adjustedW - ((cols - 1) * padding)
    local contentH = adjustedH - ((rows + 1) * padding)
    local boxW = contentW / cols
    local boxH = contentH / rows

    dashboard.boxRects = {}

    for _, box in ipairs(boxes) do
        local width, height = getBoxSize(box, boxW, boxH, padding, adjustedW, adjustedH)
        box.xOffset = xOffset
        local x, y = getBoxPosition(box, width, height, boxW, boxH, padding, adjustedW, adjustedH)
        if isFullScreen and headerLayout.height then
            y = y + headerLayout.height
        end
        dashboard.boxRects[#dashboard.boxRects + 1] = {x = x, y = y, w = width, h = height, box = box}
    end

    if isFullScreen and #headerBoxes > 0 then
        local headerCols = headerLayout.cols or 1
        local headerRows = headerLayout.rows or 1
        local headerPadding = headerLayout.padding or 0
        local headerHeight = headerLayout.height or 0

        local adjustedHeaderW = adjustDimension(windowW, headerCols, headerCols - 1, headerPadding)
        local adjustedHeaderH = adjustDimension(headerHeight, headerRows, headerRows - 1, headerPadding)
        local headerContentW = adjustedHeaderW - ((headerCols - 1) * headerPadding)
        local headerContentH = adjustedHeaderH - ((headerRows - 1) * headerPadding)
        local headerBoxW = headerContentW / headerCols
        local headerBoxH = headerContentH / headerRows

        local rightmostIndex = 1
        local rightmostX = 0
        local headerGeometries = {}

        for index, box in ipairs(headerBoxes) do
            local width, height = getBoxSize(box, headerBoxW, headerBoxH, headerPadding, adjustedHeaderW, adjustedHeaderH)
            local x, y = getBoxPosition(box, width, height, headerBoxW, headerBoxH, headerPadding, adjustedHeaderW, adjustedHeaderH)
            headerGeometries[index] = {x = x, y = y, w = width, h = height, box = box}
            if x > rightmostX then
                rightmostIndex = index
                rightmostX = x
            end
        end

        for index, geom in ipairs(headerGeometries) do
            local width = geom.w
            if index == rightmostIndex then
                width = windowW - geom.x
            end
            dashboard.boxRects[#dashboard.boxRects + 1] = {x = geom.x, y = geom.y, w = width, h = geom.h, box = geom.box}
        end
    end
end

local function ensureState()
    local nextState = fsdash.flightmode.current or "preflight"
    if nextState ~= currentState then
        currentState = nextState
        local module = loadedStates[currentState]
        if module then
            loadObjects(module)
        else
            dashboard.objectsByType = {}
            dashboard.boxRects = {}
        end
        dashboard.currentWidgetPath = getThemeForState(currentState)
        local activeModulePath = module and module.__themeDebugPath or "nil"
        local activeSignature = string.format("state=%s|selected=%s|module=%s", tostring(currentState), tostring(dashboard.currentWidgetPath), tostring(activeModulePath))
        if dashboard.themeActiveStateSignature ~= activeSignature then
            dashboard.themeActiveStateSignature = activeSignature
            appendThemeDebugLog("active " .. activeSignature)
        end
        forceFullRepaint = true
    end

    local width, height = lcd.getWindowSize()
    local sizeKey = string.format("%dx%d", width, height)
    if sizeKey ~= lastSizeKey then
        lastSizeKey = sizeKey
        forceFullRepaint = true
    end

    local module = loadedStates[currentState]
    if module then
        buildRects(module)
    else
        dashboard.boxRects = {}
    end
    return module
end

local function wakeObjects()
    local dirty = forceFullRepaint

    for _, rect in ipairs(dashboard.boxRects) do
        local object = dashboard.objectsByType[rect.box.type]
        if object and object.wakeup then
            object.wakeup(rect.box)
        end
        if not dirty and object and object.dirty and object.dirty(rect.box) then
            dirty = true
        end
    end

    return dirty
end

local function getOverlayMessage(state)
    if dashboard.themeFallbackUsed[state] and (os.clock() - (dashboard.themeFallbackTime[state] or 0)) < 10 then
        local reason = dashboard.themeFallbackReason[state]
        if type(reason) == "string" and reason ~= "" then
            return "Theme fallback " .. state .. ": " .. reason
        end
        return "Your theme did not load correctly. Falling back to default theme."
    end

    if not fsdash.session.telemetryState and state ~= "postflight" then
        return "CONNECTING"
    end

    return nil
end

local function paintObjects()
    local module = loadedStates[currentState]
    if not module then
        appendThemeFallbackLog(currentState or "unknown", getThemeForState(currentState or "preflight"), "active state module missing during paint")
        return
    end

    dashboard.utils.setBackgroundColourBasedOnTheme()

    for _, rect in ipairs(dashboard.boxRects) do
        local object = dashboard.objectsByType[rect.box.type]
        if object and object.paint then
            object.paint(rect.x, rect.y, rect.w, rect.h, rect.box)
        end
    end

end

function dashboard.loader(x, y, w, h)
    dashboard.loaders.staticLoader(dashboard, x, y, w, h)
end

function dashboard.overlaymessage(x, y, w, h, text)
    dashboard.loaders.staticOverlayMessage(dashboard, x, y, w, h, text)
end

function dashboard.create()
    ensureDashboardLibraries()
    os.mkdir("SCRIPTS:/" .. fsdash.config.preferences .. "/dashboard/")
    -- Prime runtime state so model preferences are available for initial theme selection.
    if fsdash.runtime and fsdash.runtime.wakeup then
        fsdash.runtime.wakeup()
    end
    reloadTheme()
    return {}
end

function dashboard.listThemes()
    ensureDashboardLibraries()

    local themes = {}
    local count = 0

    local function scanThemes(basePath, sourceType)
        local folders = system.listFiles(basePath)
        if not folders then
            return
        end

        for _, folder in ipairs(folders) do
            local normalizedFolder = type(folder) == "string" and folder:gsub("/+$", "") or folder
            if normalizedFolder ~= "." and normalizedFolder ~= ".." and fsdash.utils.dir_exists(basePath, normalizedFolder) then
                local initPath = basePath .. normalizedFolder .. "/init.lua"
                local chunk = loadfile(initPath)
                if chunk then
                    local ok, initTable = pcall(chunk)
                    if ok and type(initTable) == "table" and type(initTable.name) == "string" then
                        if not initTable.developer or (fsdash.preferences and fsdash.preferences.developer and fsdash.preferences.developer.devtools == true) then
                            count = count + 1
                            themes[count] = {
                                name = initTable.name,
                                configure = initTable.configure,
                                folder = normalizedFolder,
                                idx = count,
                                source = sourceType
                            }
                        end
                    end
                end
            end
        end
    end

    scanThemes(themesBasePath, "system")

    local userBasePath = "SCRIPTS:/" .. fsdash.config.preferences .. "/"
    if fsdash.utils.dir_exists(userBasePath, "dashboard") then
        scanThemes(themesUserPath, "user")
    end

    return themes
end

function dashboard.getPreference(key)
    if not fsdash.session.modelPreferences or not dashboard.currentWidgetPath then
        return nil
    end

    return fsdash.ini.getvalue(fsdash.session.modelPreferences, dashboard.currentWidgetPath, key)
end

function dashboard.savePreference(key, value)
    if not fsdash.session.modelPreferences or not fsdash.session.modelPreferencesFile or not dashboard.currentWidgetPath then
        return false
    end

    fsdash.ini.setvalue(fsdash.session.modelPreferences, dashboard.currentWidgetPath, key, value)
    return fsdash.ini.save_ini_file(fsdash.session.modelPreferencesFile, fsdash.session.modelPreferences)
end

function dashboard.resetFlightModeAsk()
    local buttons = {
        {
            label = "          OK           ",
            action = function()
                if fsdash.runtime and fsdash.runtime.resetFlight then
                    fsdash.runtime.resetFlight()
                end
                if model and type(model.resetFlight) == "function" then
                    pcall(model.resetFlight)
                end
                dashboard.closeToolbar()
                if lcd.invalidate then
                    lcd.invalidate()
                end
                return true
            end
        },
        {
            label = "CANCEL",
            action = function()
                return true
            end
        }
    }

    form.openDialog({
        title = "Reset flight",
        message = "Are you sure you want to reset the flight?",
        buttons = buttons,
        options = TEXT_LEFT
    })
end

function dashboard.menu(widget)
    return {
        {
            "Reset flight",
            function()
                dashboard.resetFlightModeAsk()
                if lcd.invalidate then
                    lcd.invalidate(widget)
                end
            end
        }
    }
end

function dashboard.paint()
    if unsupportedResolution then
        dashboard.utils.screenError("TO SMALL", true, 0.5)
        return
    end

    ensureState()
    paintObjects()
    if dashboard.toolbar and dashboard.toolbar.draw then
        dashboard.toolbar.draw(dashboard)
    end
end

function dashboard.wakeup(widget)
    local visible = lcd.isVisible(widget)
    local now = os.clock()

    if not visible then
        if (now - lastHiddenWakeAt) < hiddenWakeInterval then
            return
        end
        lastHiddenWakeAt = now
        fsdash.runtime.wakeup()
        return
    end

    local runtimeState = fsdash.runtime.wakeup()

    local width, height = lcd.getWindowSize()
    unsupportedResolution = not dashboard.utils.supportedResolution(width, height, supportedResolutions)
    if unsupportedResolution then
        lcd.invalidate(widget)
        return
    end

    if runtimeState.model_changed then
        reloadTheme()
    elseif now >= nextThemeStateCheck then
        nextThemeStateCheck = now + themeStateCheckInterval
        local currentThemeSignature = dashboard.utils.getThemeSignature()
        if currentThemeSignature ~= themeStateSignature then
            reloadTheme()
        end
    end

    if fsdash.session and fsdash.session.dashboardThemeReloadPending then
        fsdash.session.dashboardThemeReloadPending = false
        local prefFile = "SCRIPTS:/" .. fsdash.config.preferences .. "/preferences.ini"
        local freshPrefs = fsdash.ini.load_ini_file(prefFile)
        if freshPrefs and freshPrefs.dashboard and fsdash.preferences then
            fsdash.preferences.dashboard = freshPrefs.dashboard
        end
        reloadTheme()
    end

    ensureState()

    if dashboard.toolbarVisible and dashboard.toolbarLastActivityAt > 0 and (now - dashboard.toolbarLastActivityAt) >= TOOLBAR_TIMEOUT then
        dashboard.closeToolbar()
        lcd.invalidate(widget)
    end

    if wakeObjects() or runtimeState.flightmode_changed or (now - lastInvalidateAt) >= invalidateInterval then
        forceFullRepaint = false
        lastInvalidateAt = now
        lcd.invalidate(widget)
    end
end

function dashboard.event(widget, category, value, x, y)
    if gestureConsumeUntilTouchEnd and category == EVT_TOUCH then
        consumeTouchSequence(value)
        if value == TOUCH_END then
            gestureConsumeUntilTouchEnd = false
            gestureActive = false
            gestureTriggered = false
        end
        return true
    end

    if dashboard.toolbar and dashboard.toolbar.handleEvent and dashboard.toolbar.handleEvent(dashboard, widget, category, value, x, y) then
        return true
    end

    if category == EVT_KEY and value == KEY_PAGE_LONG and lcd.hasFocus() then
        dashboard.openToolbar()
        lcd.invalidate(widget)
        if system.killEvents then
            system.killEvents(value)
            if KEY_PAGE_UP and KEY_PAGE_UP ~= value then
                system.killEvents(KEY_PAGE_UP)
            end
        end
        return true
    end

    if category == EVT_TOUCH and (value == TOUCH_START or value == TOUCH_END) and x and y then
        gestureActive = true
        gestureStartX = x
        gestureStartY = y
        gestureTriggered = false
    end

    if category == EVT_TOUCH and value == TOUCH_MOVE then
        if not gestureActive and x and y then
            gestureActive = true
            gestureStartX = x
            gestureStartY = y
            gestureTriggered = false
        end

        if gestureActive and not gestureTriggered and x and y then
            local dx = x - gestureStartX
            local dy = y - gestureStartY
            if math.abs(dx) <= GESTURE_MAX_DX then
                if dy <= -GESTURE_MIN_DY then
                    gestureTriggered = true
                    gestureConsumeUntilTouchEnd = true
                    consumeTouchSequence(TOUCH_START)
                    dashboard.openToolbar()
                    lcd.invalidate(widget)
                    return true
                elseif dy >= GESTURE_MIN_DY then
                    gestureTriggered = true
                    gestureConsumeUntilTouchEnd = true
                    consumeTouchSequence(TOUCH_START)
                    dashboard.closeToolbar()
                    lcd.invalidate(widget)
                    return true
                end
            end
        end
    end

    if dashboard.toolbarVisible then
        return false
    end

    local indices = {}
    for index, rect in ipairs(dashboard.boxRects or {}) do
        if rect and rect.box and rect.box.onpress then
            indices[#indices + 1] = index
        end
    end

    if category == EVT_KEY and lcd.hasFocus() then
        local count = #indices
        if count == 0 then
            dashboard.selectedBoxIndex = nil
            return false
        end

        local current = dashboard.selectedBoxIndex or indices[1]
        local pos = 1
        for index, rectIndex in ipairs(indices) do
            if rectIndex == current then
                pos = index
                break
            end
        end

        if value == ROTARY_LEFT then
            pos = pos - 1
            if pos < 1 then
                pos = count
            end
            dashboard.selectedBoxIndex = indices[pos]
            lcd.invalidate(widget)
            return true
        elseif value == KEY_ROTARY_RIGHT then
            pos = pos + 1
            if pos > count then
                pos = 1
            end
            dashboard.selectedBoxIndex = indices[pos]
            lcd.invalidate(widget)
            return true
        elseif value == KEY_ENTER_BREAK then
            local selectedIndex = dashboard.selectedBoxIndex
            local rect = selectedIndex and dashboard.boxRects[selectedIndex] or nil
            if not rect then
                dashboard.selectedBoxIndex = indices[1]
                lcd.invalidate(widget)
                return true
            end
            if rect.box and rect.box.onpress then
                rect.box.onpress(widget, rect.box, rect.x, rect.y, category, value)
                if system.killEvents and KEY_ENTER_FIRST then
                    system.killEvents(KEY_ENTER_FIRST)
                end
                return true
            end
        end
    end

    if value == KEY_DOWN_BREAK and dashboard.selectedBoxIndex then
        dashboard.selectedBoxIndex = nil
        lcd.invalidate(widget)
        return true
    end

    if category == EVT_TOUCH and value == TOUCH_END and lcd.hasFocus() and x and y then
        for index, rect in ipairs(dashboard.boxRects or {}) do
            if x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h then
                if rect.box and rect.box.onpress then
                    dashboard.selectedBoxIndex = index
                    lcd.invalidate(widget)
                    rect.box.onpress(widget, rect.box, x, y, category, value)
                    if system.killEvents then
                        system.killEvents(TOUCH_START)
                    end
                    return true
                end
            end
        end
    end

    return false
end

return dashboard
