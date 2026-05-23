--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local fsdash = {
    session = {},
    widgets = {},
    tools = {},
    theme = {version = 0},
    flightmode = {current = "preflight"},
    app = {guiIsRunning = false}
}

package.loaded.FSDash = fsdash

if not FONT_M then
    FONT_M = FONT_STD
end

fsdash.config = {
    toolName = "FSDash",
    baseDir = "FSDash",
    preferences = "FSDash.user",
    version = {major = 2, minor = 3, revision = 0, suffix = "DEV"},
    ethosVersion = {1, 6, 2},
    supportedMspApiVersion = {"12.07", "12.08", "12.09"}
}

local userPreferenceDefaults = {
    general = {
        iconsize = 2,
        syncname = false,
        gimbalsupression = 0.85
    },
    localizations = {
        temperature_unit = 0,
        altitude_unit = 0
    },
    dashboard = {
        theme_preflight = "system/default",
        theme_inflight = "system/default",
        theme_postflight = "system/default"
    },
    events = {
        armed = true,
        voltage = true,
        fuel = true,
        profile = true,
        inflight = true
    },
    switches = {},
    developer = {
        compile = true,
        devtools = false,
        logtofile = false,
        loglevel = "off",
        logmsp = false,
        logmspQueue = false,
        memstats = false,
        mspexpbytes = 8,
        apiversion = 2,
        overlaygrid = false,
        overlaystats = false,
        logobjprof = false,
        telemetrytrace = false
    },
    menulastselected = {}
}

local function ensureSharedModules()
    if not fsdash.ini then
        fsdash.ini = assert(loadfile("lib/ini.lua"))()
    end

    if not fsdash.utils then
        fsdash.utils = assert(loadfile("lib/utils.lua"))(fsdash.config)
    end

    if not fsdash._sessionInitialized then
        fsdash.utils.session()
        fsdash._sessionInitialized = true
    end

    if not fsdash.preferences then
        local prefDir = "SCRIPTS:/" .. fsdash.config.preferences
        local prefFile = prefDir .. "/preferences.ini"
        os.mkdir(prefDir)

        local existing = fsdash.ini.load_ini_file(prefFile) or {}
        local merged = fsdash.ini.merge_ini_tables(existing, userPreferenceDefaults)
        fsdash.preferences = merged

        if not fsdash.ini.ini_tables_equal(existing, merged) then
            fsdash.ini.save_ini_file(prefFile, merged)
        end
    end
end

local function ensureWidgetModules()
    ensureSharedModules()

    fsdash.tasks = fsdash.tasks or {}

    if not fsdash.telemetry then
        fsdash.telemetry = assert(loadfile("lib/telemetry.lua"))(fsdash.config)
    end
    fsdash.tasks.telemetry = fsdash.telemetry

    if not fsdash.logging then
        fsdash.logging = assert(loadfile("lib/logging.lua"))(fsdash.config)
    end
    fsdash.tasks.logging = fsdash.logging

    if not fsdash.sensors then
        fsdash.sensors = assert(loadfile("lib/sensors.lua"))(fsdash.config)
    end

    if not fsdash.events then
        fsdash.events = assert(loadfile("lib/events.lua"))(fsdash.config)
    end

    if not fsdash.runtime then
        fsdash.runtime = assert(loadfile("lib/runtime.lua"))(fsdash.config)
    end

    if not fsdash.widgets.dashboard then
        fsdash.widgets.dashboard = assert(loadfile("widgets/dashboard/dashboard.lua"))(fsdash.config)
    end

    if not fsdash.widgets.dashboardConfigure then
        fsdash.widgets.dashboardConfigure = assert(loadfile("widgets/dashboard/configure.lua"))(fsdash.config)
    end
end

local function ensureLogsTool()
    ensureSharedModules()

    if not fsdash.logs then
        fsdash.logs = assert(loadfile("lib/logs.lua"))(fsdash.config)
    end

    if not fsdash.tools.logs then
        fsdash.tools.logs = assert(loadfile("tools/logs.lua"))(fsdash.config)
    end
end

function fsdash.version()
    local version = fsdash.config.version
    return {
        version = string.format("%d.%d.%d-%s", version.major, version.minor, version.revision, version.suffix),
        major = version.major,
        minor = version.minor,
        revision = version.revision,
        suffix = version.suffix
    }
end

local function callWidget(method, ...)
    ensureWidgetModules()
    return fsdash.widgets.dashboard[method](...)
end

local function callWidgetConfigure(method, ...)
    ensureWidgetModules()
    return fsdash.widgets.dashboardConfigure[method](...)
end

local function callLogsTool(method, ...)
    ensureLogsTool()
    local tool = fsdash.tools.logs
    local handler = tool and tool[method]
    if handler then
        return handler(...)
    end
end

local function closeLogsTool(...)
    local tool = fsdash.tools and fsdash.tools.logs
    if tool and tool.close then
        return tool.close(...)
    end
end

local function loadToolIcon(path)
    if not lcd or not path then
        return nil
    end

    local candidates = {
        path,
        "SCRIPTS:/" .. fsdash.config.baseDir .. "/" .. path
    }

    for _, candidate in ipairs(candidates) do
        if lcd.loadMask then
            local ok, loaded = pcall(lcd.loadMask, candidate)
            if ok and loaded then
                return loaded
            end
        end

        if lcd.loadBitmap then
            local ok, loaded = pcall(lcd.loadBitmap, candidate)
            if ok and loaded then
                return loaded
            end
        end
    end

    return nil
end

local function registerWidget()
    system.registerWidget({
        key = "FS-Dash Dashboard",
        name = "FSDashboard",
        create = function(...)
            return callWidget("create", ...)
        end,
        configure = function(...)
            return callWidgetConfigure("configure", ...)
        end,
        paint = function(...)
            return callWidget("paint", ...)
        end,
        event = function(...)
            return callWidget("event", ...)
        end,
        menu = function(...)
            return callWidget("menu", ...)
        end,
        wakeup = function(...)
            return callWidget("wakeup", ...)
        end,
        read = function(...)
            return callWidgetConfigure("read", ...)
        end,
        write = function(...)
            return callWidgetConfigure("write", ...)
        end,
        title = false,
        persistent = false
    })
end

local function registerLogsTool()
    if not system.registerSystemTool then
        return
    end

    system.registerSystemTool({
        name = "FSDashboard Logs",
        icon = loadToolIcon("app/gfx/icon.png"),
        create = function(...)
            return callLogsTool("create", ...)
        end,
        wakeup = function(...)
            return callLogsTool("wakeup", ...)
        end,
        paint = function(...)
            return callLogsTool("paint", ...)
        end,
        event = function(...)
            return callLogsTool("event", ...)
        end,
        close = function(...)
            return closeLogsTool(...)
        end
    })
end

local function init()
    ensureSharedModules()
    fsdash.simevent = fsdash.simevent or {telemetry_state = true}
    registerWidget()
    registerLogsTool()
end

return {init = init}
