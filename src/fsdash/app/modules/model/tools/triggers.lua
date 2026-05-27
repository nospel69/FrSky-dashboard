--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local dashx = require("FSDash")

local enableWakeup = false

local function openPage(pageIdx, title, script)
    enableWakeup = true
    dashx.app.triggers.closeProgressLoader = true
    form.clear()

    dashx.app.lastIdx = pageIdx
    dashx.app.lastTitle = title
    dashx.app.lastScript = script

    dashx.app.ui.fieldHeader("Model" .. " / " .. "Triggers")

    local formFieldCount = 0
    local formLineCnt = 0
    dashx.app.formLines = {}
    dashx.app.formFields = {}

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Arm Switch")
    dashx.app.formFields[formFieldCount] = form.addSwitchField(dashx.app.formLines[formLineCnt], nil, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.model.armswitch then
            local category, member, options = dashx.session.modelPreferences.model.armswitch:match("([^:]+):([^:]+):([^:]+)")
            if category and member then return system.getSource({category = category, member = member, options = options}) end
        end
        return nil
    end, function(newValue)
        if dashx.session.modelPreferences then
            local member = newValue:member()
            local category = newValue:category()
            local options = newValue:options()
            dashx.session.modelPreferences.model.armswitch = category .. ":" .. member .. ":" .. options
        end
    end)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Inflight Detection")
    dashx.app.formFields[formFieldCount] = form.addChoiceField(dashx.app.formLines[formLineCnt], nil, {"RPM-based", "Switch-based"}, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.model.inflightswitch then
            local spec = dashx.session.modelPreferences.model.inflightswitch
            if spec == "RPM" or spec == false then
                return 0  -- RPM-based
            else
                return 1  -- Switch-based
            end
        end
        return 0  -- Default to RPM-based
    end, function(newValue)
        if dashx.session.modelPreferences then
            if newValue == 0 then
                dashx.session.modelPreferences.model.inflightswitch = "RPM"
            else
                dashx.session.modelPreferences.model.inflightswitch = false
            end
        end
    end)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Inflight Switch")
    dashx.app.formFields[formFieldCount] = form.addSwitchField(dashx.app.formLines[formLineCnt], nil, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.model.inflightswitch then
            local spec = dashx.session.modelPreferences.model.inflightswitch
            if spec == "RPM" or spec == false then
                return nil  -- No switch when using RPM-based
            end
            local category, member, options = spec:match("([^:]+):([^:]+):([^:]+)")
            if category and member then return system.getSource({category = category, member = member, options = options}) end
        end
        return nil
    end, function(newValue)
        if dashx.session.modelPreferences then
            if newValue then
                local member = newValue:member()
                local category = newValue:category()
                local options = newValue:options()
                dashx.session.modelPreferences.model.inflightswitch = category .. ":" .. member .. ":" .. options
            end
        end
    end)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Inflight Switch Delay")
    dashx.app.formFields[formFieldCount] = form.addNumberField(dashx.app.formLines[formLineCnt], nil, 0, 120, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.model.inflightswitch_delay then return dashx.session.modelPreferences.model.inflightswitch_delay end
        return nil
    end, function(newValue) if dashx.session.modelPreferences then dashx.session.modelPreferences.model.inflightswitch_delay = newValue end end)
    dashx.app.formFields[formFieldCount]:suffix("s")
    dashx.app.formFields[formFieldCount]:default(20)

end

local function onNavMenu()
    dashx.app.ui.progressDisplay()
    dashx.app.ui.openPage(pageIdx, "Model", "model/model.lua")
end

local function onSaveMenu()
    local buttons = {
        {
            label = "                OK                ",
            action = function()
                local msg = "Save current page to radio?"
                dashx.app.ui.progressDisplaySave(msg:gsub("%?$", "."))

                if dashx.session.mcu_id and dashx.session.modelPreferencesFile then dashx.ini.save_ini_file(dashx.session.modelPreferencesFile, dashx.session.modelPreferences) end

                dashx.app.triggers.closeSave = true

                if dashx.tasks and dashx.tasks.sensors then dashx.tasks.sensors.reset() end

                return true
            end
        }, {label = "CANCEL", action = function() return true end}
    }

    form.openDialog({width = nil, title = "@i18n(app.modules.profile_select.save_dashx.preferences.model)@", message = "Save current page to radio?", buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})
end

local function event(widget, category, value, x, y)

    if (category == EVT_CLOSE and value == 0) or value == 35 then
        dashx.app.ui.openPage(pageIdx, "Model", "model/model.lua")
        return true
    end
end

local function wakeup() if enableWakeup then if not dashx.session.isConnected then dashx.app.ui.openMainMenu() end end end

return {event = event, openPage = openPage, wakeup = wakeup, onNavMenu = onNavMenu, onSaveMenu = onSaveMenu, navButtons = {menu = true, save = true, reload = false, tool = false, help = false}, API = {}}
