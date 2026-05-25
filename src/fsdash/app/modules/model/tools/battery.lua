--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local dashx = require("FSDash")
local settings = {}
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
    dashx.app.formLines[formLineCnt] = form.addLine("Calculate Fuel Using")
    dashx.app.formFields[formFieldCount] = form.addChoiceField(dashx.app.formLines[formLineCnt], nil, {{"Current Sensor", 0}, {"Voltage Sensor", 1}}, function()
        if dashx.session.modelPreferences then return dashx.session.modelPreferences.battery.calc_local end
        return nil
    end, function(newValue) if dashx.session.modelPreferences then dashx.session.modelPreferences.battery.calc_local = newValue end end)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Battery Capacity")
    dashx.app.formFields[formFieldCount] = form.addNumberField(dashx.app.formLines[formLineCnt], nil, 0, 10000000, function()
        if dashx.session.modelPreferences and settings then return dashx.session.modelPreferences.battery.batteryCapacity end
        return nil
    end, function(newValue) if dashx.session.modelPreferences then dashx.session.modelPreferences.battery.batteryCapacity = newValue end end)
    dashx.app.formFields[formFieldCount]:suffix("mAh")
    dashx.app.formFields[formFieldCount]:default(2200)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Battery Cells")
    dashx.app.formFields[formFieldCount] = form.addNumberField(dashx.app.formLines[formLineCnt], nil, 1, 24, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.battery then return dashx.session.modelPreferences.battery.batteryCellCount end
        return nil
    end, function(newValue) if dashx.session.modelPreferences then dashx.session.modelPreferences.battery.batteryCellCount = newValue end end)

    dashx.app.formFields[formFieldCount]:default(3)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Cell Warning Voltage")
    dashx.app.formFields[formFieldCount] = form.addNumberField(dashx.app.formLines[formLineCnt], nil, 5, 600, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.battery then return dashx.session.modelPreferences.battery.vbatwarningcellvoltage end
        return nil
    end, function(newValue) if dashx.session.modelPreferences then dashx.session.modelPreferences.battery.vbatwarningcellvoltage = newValue end end)
    dashx.app.formFields[formFieldCount]:suffix("v")
    dashx.app.formFields[formFieldCount]:default(35)
    dashx.app.formFields[formFieldCount]:decimals(1)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Cell Minimum Voltage")
    dashx.app.formFields[formFieldCount] = form.addNumberField(dashx.app.formLines[formLineCnt], nil, 5, 600, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.battery then return dashx.session.modelPreferences.battery.vbatmincellvoltage end
        return nil
    end, function(newValue) if dashx.session.modelPreferences then dashx.session.modelPreferences.battery.vbatmincellvoltage = newValue end end)
    dashx.app.formFields[formFieldCount]:suffix("v")
    dashx.app.formFields[formFieldCount]:default(33)
    dashx.app.formFields[formFieldCount]:decimals(1)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Cell Maximum Voltage")
    dashx.app.formFields[formFieldCount] = form.addNumberField(dashx.app.formLines[formLineCnt], nil, 5, 600, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.battery then return dashx.session.modelPreferences.battery.vbatmaxcellvoltage end
        return nil
    end, function(newValue) if dashx.session.modelPreferences then dashx.session.modelPreferences.battery.vbatmaxcellvoltage = newValue end end)
    dashx.app.formFields[formFieldCount]:suffix("v")
    dashx.app.formFields[formFieldCount]:default(43)
    dashx.app.formFields[formFieldCount]:decimals(1)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Cell Full Voltage")
    dashx.app.formFields[formFieldCount] = form.addNumberField(dashx.app.formLines[formLineCnt], nil, 5, 600, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.battery then return dashx.session.modelPreferences.battery.vbatfullcellvoltage end
        return nil
    end, function(newValue) if dashx.session.modelPreferences then dashx.session.modelPreferences.battery.vbatfullcellvoltage = newValue end end)
    dashx.app.formFields[formFieldCount]:suffix("v")
    dashx.app.formFields[formFieldCount]:default(41)
    dashx.app.formFields[formFieldCount]:decimals(1)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("Consumption Warning %")
    dashx.app.formFields[formFieldCount] = form.addNumberField(dashx.app.formLines[formLineCnt], nil, 0, 100, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.battery then return dashx.session.modelPreferences.battery.consumptionWarningPercentage end
        return nil
    end, function(newValue) if dashx.session.modelPreferences then dashx.session.modelPreferences.battery.consumptionWarningPercentage = newValue end end)
    dashx.app.formFields[formFieldCount]:suffix("%")
    dashx.app.formFields[formFieldCount]:default(30)

    formFieldCount = formFieldCount + 1
    formLineCnt = formLineCnt + 1
    dashx.app.formLines[formLineCnt] = form.addLine("@i18n(app.modules.model.consumption_scale)@")
    dashx.app.formFields[formFieldCount] = form.addNumberField(dashx.app.formLines[formLineCnt], nil, 50, 200, function()
        if dashx.session.modelPreferences and dashx.session.modelPreferences.battery then return dashx.session.modelPreferences.battery.consumptionScale end
        return nil
    end, function(newValue) if dashx.session.modelPreferences then dashx.session.modelPreferences.battery.consumptionScale = newValue end end)
    dashx.app.formFields[formFieldCount]:suffix("%")
    dashx.app.formFields[formFieldCount]:default(100)

    enableWakeup = true

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

                if dashx.session.mcu_id and dashx.session.modelPreferencesFile then
                    for key, value in pairs(settings) do dashx.session.modelPreferences.battery[key] = value end

                    dashx.ini.save_ini_file(dashx.session.modelPreferencesFile, dashx.session.modelPreferences)
                end

                dashx.app.triggers.closeSave = true

                if dashx.tasks and dashx.tasks.sensors then dashx.tasks.sensors.reset() end

                return true
            end
        }, {label = "CANCEL", action = function() return true end}
    }

    form.openDialog({width = nil, title = "Save settings", message = "Save current page to radio?", buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})
end

local function event(widget, category, value, x, y)

    if (category == EVT_CLOSE and value == 0) or value == 35 then
        dashx.app.ui.openPage(pageIdx, "Model", "model/model.lua")
        return true
    end
end

local function wakeup()
    if enableWakeup then

        if not dashx.tasks.telemetry.getSensorSource("consumption") then
            dashx.session.modelPreferences.battery.calc_local = 1
            dashx.app.formFields[1]:enable(false)
        end

        if not dashx.session.isConnected then dashx.app.ui.openMainMenu() end

    end
end

return {event = event, openPage = openPage, wakeup = wakeup, onNavMenu = onNavMenu, onSaveMenu = onSaveMenu, navButtons = {menu = true, save = true, reload = false, tool = false, help = false}, API = {}}
