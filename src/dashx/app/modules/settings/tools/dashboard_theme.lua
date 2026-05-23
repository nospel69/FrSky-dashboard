--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local dashx = require("FSDash")
local settings = {}
local settings_model = {}

local themeList = dashx.widgets.dashboard.listThemes()
local formattedThemes = {}
local formattedThemesModel = {}

local enableWakeup = false
local prevConnectedState = nil

local function generateThemeList()

    settings = dashx.preferences.dashboard

    if dashx.session.modelPreferences then
        settings_model = dashx.session.modelPreferences.dashboard
    else
        settings_model = {}
    end

    for i, theme in ipairs(themeList) do table.insert(formattedThemes, {theme.name, theme.idx}) end

    table.insert(formattedThemesModel, {"Disabled", 0})
    for i, theme in ipairs(themeList) do table.insert(formattedThemesModel, {theme.name, theme.idx}) end
end

local function openPage(pageIdx, title, script)
    enableWakeup = true
    dashx.app.triggers.closeProgressLoader = true
    form.clear()

    dashx.app.lastIdx = pageIdx
    dashx.app.lastTitle = title
    dashx.app.lastScript = script

    dashx.app.ui.fieldHeader("Settings" .. " / " .. "Dashboard" .. " / " .. "Theme")
    dashx.app.formLineCnt = 0

    local formFieldCount = 0

    generateThemeList()

    local global_panel = form.addExpansionPanel("Default theme for all models")
    global_panel:open(true)

    formFieldCount = formFieldCount + 1
    dashx.app.formLineCnt = dashx.app.formLineCnt + 1
    dashx.app.formLines[dashx.app.formLineCnt] = global_panel:addLine("Preflight Theme")

    dashx.app.formFields[formFieldCount] = form.addChoiceField(dashx.app.formLines[dashx.app.formLineCnt], nil, formattedThemes, function()
        if dashx.preferences and dashx.preferences.dashboard then
            local folderName = settings.theme_preflight
            for _, theme in ipairs(themeList) do if (theme.source .. "/" .. theme.folder) == folderName then return theme.idx end end
        end
        return nil
    end, function(newValue)
        if dashx.preferences and dashx.preferences.dashboard then
            local theme = themeList[newValue]
            if theme then settings.theme_preflight = theme.source .. "/" .. theme.folder end
        end
    end)

    formFieldCount = formFieldCount + 1
    dashx.app.formLineCnt = dashx.app.formLineCnt + 1
    dashx.app.formLines[dashx.app.formLineCnt] = global_panel:addLine("Inflight Theme")

    dashx.app.formFields[formFieldCount] = form.addChoiceField(dashx.app.formLines[dashx.app.formLineCnt], nil, formattedThemes, function()
        if dashx.preferences and dashx.preferences.dashboard then
            local folderName = settings.theme_inflight
            for _, theme in ipairs(themeList) do if (theme.source .. "/" .. theme.folder) == folderName then return theme.idx end end
        end
        return nil
    end, function(newValue)
        if dashx.preferences and dashx.preferences.dashboard then
            local theme = themeList[newValue]
            if theme then settings.theme_inflight = theme.source .. "/" .. theme.folder end
        end
    end)

    formFieldCount = formFieldCount + 1
    dashx.app.formLineCnt = dashx.app.formLineCnt + 1
    dashx.app.formLines[dashx.app.formLineCnt] = global_panel:addLine("Postflight Theme")

    dashx.app.formFields[formFieldCount] = form.addChoiceField(dashx.app.formLines[dashx.app.formLineCnt], nil, formattedThemes, function()
        if dashx.preferences and dashx.preferences.dashboard then
            local folderName = settings.theme_postflight
            for _, theme in ipairs(themeList) do if (theme.source .. "/" .. theme.folder) == folderName then return theme.idx end end
        end
        return nil
    end, function(newValue)
        if dashx.preferences and dashx.preferences.dashboard then
            local theme = themeList[newValue]
            if theme then settings.theme_postflight = theme.source .. "/" .. theme.folder end
        end
    end)

    local model_panel = form.addExpansionPanel("Optional theme for this model")
    model_panel:open(false)

    formFieldCount = formFieldCount + 1
    dashx.app.formLineCnt = dashx.app.formLineCnt + 1
    dashx.app.formLines[dashx.app.formLineCnt] = model_panel:addLine("Preflight Theme")

    dashx.app.formFields[formFieldCount] = form.addChoiceField(dashx.app.formLines[dashx.app.formLineCnt], nil, formattedThemesModel, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences then
            local folderName = settings_model.theme_preflight
            for _, theme in ipairs(themeList) do if (theme.source .. "/" .. theme.folder) == folderName then return theme.idx end end
        end
        return nil
    end, function(newValue)
        if dashx.session.modelPreferences and dashx.session.modelPreferences then
            local theme = themeList[newValue]
            if theme then
                settings_model.theme_preflight = theme.source .. "/" .. theme.folder
            else
                settings_model.theme_preflight = "nil"
            end
        end
    end)
    dashx.app.formFields[formFieldCount]:enable(false)

    formFieldCount = formFieldCount + 1
    dashx.app.formLineCnt = dashx.app.formLineCnt + 1
    dashx.app.formLines[dashx.app.formLineCnt] = model_panel:addLine("Inflight Theme")

    dashx.app.formFields[formFieldCount] = form.addChoiceField(dashx.app.formLines[dashx.app.formLineCnt], nil, formattedThemesModel, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences then
            local folderName = settings_model.theme_inflight
            for _, theme in ipairs(themeList) do if (theme.source .. "/" .. theme.folder) == folderName then return theme.idx end end
        end
        return nil
    end, function(newValue)
        if dashx.session.modelPreferences and dashx.session.modelPreferences then
            local theme = themeList[newValue]
            if theme then
                settings_model.theme_inflight = theme.source .. "/" .. theme.folder
            else
                settings_model.theme_inflight = "nil"
            end
        end
    end)
    dashx.app.formFields[formFieldCount]:enable(false)

    formFieldCount = formFieldCount + 1
    dashx.app.formLineCnt = dashx.app.formLineCnt + 1
    dashx.app.formLines[dashx.app.formLineCnt] = model_panel:addLine("Postflight Theme")

    dashx.app.formFields[formFieldCount] = form.addChoiceField(dashx.app.formLines[dashx.app.formLineCnt], nil, formattedThemesModel, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences then
            local folderName = settings_model.theme_postflight
            for _, theme in ipairs(themeList) do if (theme.source .. "/" .. theme.folder) == folderName then return theme.idx end end
        end
        return nil
    end, function(newValue)
        if dashx.preferences and dashx.preferences.dashboard then
            local theme = themeList[newValue]
            if theme then
                settings_model.theme_postflight = theme.source .. "/" .. theme.folder
            else
                settings_model.theme_postflight = "nil"
            end
        end
    end)
    dashx.app.formFields[formFieldCount]:enable(false)

end

local function onNavMenu()
    dashx.app.ui.progressDisplay(nil, nil, true)
    dashx.app.ui.openPage(pageIdx, "Dashboard", "settings/tools/dashboard.lua")
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

                if dashx.session.isConnected and dashx.session.mcu_id and dashx.session.modelPreferencesFile then
                    for key, value in pairs(settings_model) do dashx.session.modelPreferences.dashboard[key] = value end
                    dashx.ini.save_ini_file(dashx.session.modelPreferencesFile, dashx.session.modelPreferences)
                end

                dashx.session.dashboardThemeReloadPending = true

                dashx.app.triggers.closeSave = true
                return true
            end
        }, {label = "CANCEL", action = function() return true end}
    }

    form.openDialog({width = nil, title = "Save settings", message = "Save current page to radio?", buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})
end

local function event(widget, category, value, x, y)

    if category == EVT_CLOSE and value == 0 or value == 35 then
        dashx.app.ui.openPage(pageIdx, "Dashboard", "settings/tools/dashboard.lua")
        return true
    end
end

local function wakeup()
    if not enableWakeup then return end

    local currState = (dashx.session.isConnected and dashx.session.mcu_id) and true or false

    if currState ~= prevConnectedState then

        if currState then
            generateThemeList()
            for i = 4, 6 do dashx.app.formFields[i]:values(formattedThemesModel) end
        end

        for i = 4, 6 do dashx.app.formFields[i]:enable(currState) end

        prevConnectedState = currState
    end
end

return {event = event, openPage = openPage, wakeup = wakeup, onNavMenu = onNavMenu, onSaveMenu = onSaveMenu, navButtons = {menu = true, save = true, reload = false, tool = false, help = false}, API = {}}
