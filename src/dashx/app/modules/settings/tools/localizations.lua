--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local dashx = require("dashx")
local settings = {}
local enableWakeup = false

local function openPage(pageIdx, title, script)
    enableWakeup = true
    dashx.app.triggers.closeProgressLoader = true
    form.clear()

    dashx.app.lastIdx = pageIdx
    dashx.app.lastTitle = title
    dashx.app.lastScript = script

    dashx.app.ui.fieldHeader("Settings" .. " / " .. "Dashboard" .. " / " .. "Localization")
    dashx.session.formLineCnt = 0

    local formFieldCount = 0

    settings = dashx.preferences.localizations

    formFieldCount = formFieldCount + 1
    dashx.session.formLineCnt = dashx.session.formLineCnt + 1
    dashx.app.formLines[dashx.session.formLineCnt] = form.addLine("Temperature Unit")
    dashx.app.formFields[formFieldCount] = form.addChoiceField(dashx.app.formLines[dashx.session.formLineCnt], nil, {{"Celsius", 0}, {"Fahrenheit", 1}},
                                               function() if dashx.preferences and dashx.preferences.localizations then return settings.temperature_unit or 0 end end, function(newValue) if dashx.preferences and dashx.preferences.localizations then settings.temperature_unit = newValue end end)

    formFieldCount = formFieldCount + 1
    dashx.session.formLineCnt = dashx.session.formLineCnt + 1
    dashx.app.formLines[dashx.session.formLineCnt] = form.addLine("Altitude Unit")
    dashx.app.formFields[formFieldCount] = form.addChoiceField(dashx.app.formLines[dashx.session.formLineCnt], nil, {{"Meters", 0}, {"Feet", 1}},
                                               function() if dashx.preferences and dashx.preferences.localizations then return settings.altitude_unit or 0 end end, function(newValue) if dashx.preferences and dashx.preferences.localizations then settings.altitude_unit = newValue end end)

end

local function onNavMenu()
    dashx.app.ui.progressDisplay()
    dashx.app.ui.openPage(pageIdx, "Settings", "settings/settings.lua")
    return true
end

local function onSaveMenu()
    local buttons = {
        {
            label = "                OK                ",
            action = function()
                local msg = "Save current page to radio?"
                dashx.app.ui.progressDisplaySave(msg:gsub("%?$", "."))
                for key, value in pairs(settings) do dashx.preferences.dashboard[key] = value end
                dashx.ini.save_ini_file("SCRIPTS:/" .. dashx.config.preferences .. "/preferences.ini", dashx.preferences)

                dashx.widgets.dashboard.reload_themes()

                dashx.app.triggers.closeSave = true
                return true
            end
        }, {label = "CANCEL", action = function() return true end}
    }

    form.openDialog({width = nil, title = "Save settings", message = "Save current page to radio?", buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})
end

local function event(widget, category, value, x, y)

    if category == EVT_CLOSE and value == 0 or value == 35 then
        dashx.app.ui.openPage(pageIdx, "Settings", "settings/settings.lua")
        return true
    end
end

return {event = event, openPage = openPage, wakeup = wakeup, onNavMenu = onNavMenu, onSaveMenu = onSaveMenu, navButtons = {menu = true, save = true, reload = false, tool = false, help = false}, API = {}}
