--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local dashx = require("FSDash")

local configui = {}
local INFLIGHT_MODE_CHOICES = {
    {"RPM-based", 0},
    {"Switch-based", 1}
}

local function isInflightRpmMode(spec)
    return spec == "RPM"
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function addLine(parent, label)
    if parent and parent.addLine then
        return parent:addLine(label)
    end
    return form.addLine(label)
end

local function ensureWidgetDefaults(widget)
    if widget == nil then
        widget = {}
    end
    dashx.runtime.readWidgetSettings(widget)
    return widget
end

local function persistWidgetSettings(widget)
    if not widget then
        return false
    end
    return dashx.runtime.writeWidgetSettings(widget)
end

local function getModelThemeValue(widget)
    local value = widget.theme_preflight
    if value == nil or value == false or value == "nil" then
        return "system/default"
    end
    return value
end

local function normalizeThemePath(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("/+$", "")
end

local function buildModelThemeChoices(themeList)
    local choices = {}
    local byValue = {}
    local firstIdx = nil

    for _, theme in ipairs(themeList or {}) do
        local value = normalizeThemePath(theme.source .. "/" .. theme.folder)
        local label = theme.name or theme.folder or value
        choices[#choices + 1] = {label, theme.idx}
        byValue[value] = theme.idx
        if firstIdx == nil then
            firstIdx = theme.idx
        end
    end

    return choices, byValue, firstIdx
end

local function encodeModelThemeChoice(widget, byValue, firstIdx)
    local storedValue = normalizeThemePath(getModelThemeValue(widget))
    return byValue[storedValue] or byValue["system/default"] or firstIdx
end

local function applyModelThemeChoice(widget, themeList, selectedValue)
    local value = "system/default"

    for _, theme in ipairs(themeList or {}) do
        if theme.idx == selectedValue then
            value = normalizeThemePath(theme.source .. "/" .. theme.folder)
            break
        end
    end

    widget.theme_preflight = value
    widget.theme_inflight = value
    widget.theme_postflight = value
end

local function decodeSwitchSpec(spec)
    if type(spec) ~= "string" or spec == "" or spec == "false" then
        return nil
    end

    local category, member, options = spec:match("([^:]+):([^:]+):([^:]+)")
    if not category or not member then
        return nil
    end

    return system.getSource({
        category = tonumber(category) or category,
        member = tonumber(member) or member,
        options = tonumber(options) or options
    })
end

local function encodeSwitchSource(source)
    if not source then
        return false
    end

    return table.concat({source:category(), source:member(), source:options()}, ":")
end

function configui.read(widget)
    if not widget or not widget._modelKey then
        widget = ensureWidgetDefaults(widget)
    end
    return true
end

function configui.write(widget)
    if not widget then
        return true
    end

    if next(widget) == nil then
        return true
    end

    return dashx.runtime.writeWidgetSettings(widget)
end

function configui.configure(widget)
    if not widget or not widget._modelKey then
        widget = ensureWidgetDefaults(widget)
    end

    local themeLine = addLine(nil, "Theme for this model")
    local themeList = dashx.widgets.dashboard.listThemes()
    local themeChoices, themeValueMap, firstThemeIdx = buildModelThemeChoices(themeList)
    form.addChoiceField(themeLine, nil, themeChoices, function()
        return encodeModelThemeChoice(widget, themeValueMap, firstThemeIdx)
    end, function(value)
        applyModelThemeChoice(widget, themeList, value)
        persistWidgetSettings(widget)
    end)

    local batteryPanel = form.addExpansionPanel("Battery")
    batteryPanel:open(true)

    local fuelModeLine = addLine(batteryPanel, "Calculate Fuel Using")
    form.addChoiceField(fuelModeLine, nil, {
        {"Current Sensor", 0},
        {"Voltage Sensor", 1}
    }, function()
        return clamp(math.floor(tonumber(widget.calc_local) or 0), 0, 1)
    end, function(value)
        widget.calc_local = clamp(math.floor(tonumber(value) or 0), 0, 1)
        persistWidgetSettings(widget)
    end)

    local capacityLine = addLine(batteryPanel, "Battery Capacity")
    local capacityField = form.addNumberField(capacityLine, nil, 0, 10000000, function()
        return math.floor(tonumber(widget.batteryCapacity) or 2200)
    end, function(value)
        widget.batteryCapacity = clamp(math.floor(tonumber(value) or 2200), 0, 10000000)
        persistWidgetSettings(widget)
    end)
    if capacityField and capacityField.suffix then
        capacityField:suffix("mAh")
    end

    local cellsLine = addLine(batteryPanel, "Battery Cells")
    local cellsField = form.addNumberField(cellsLine, nil, 1, 24, function()
        return math.floor(tonumber(widget.batteryCellCount) or 3)
    end, function(value)
        widget.batteryCellCount = clamp(math.floor(tonumber(value) or 3), 1, 24)
        persistWidgetSettings(widget)
    end)
    if cellsField and cellsField.suffix then
        cellsField:suffix("S")
    end

    local warnLine = addLine(batteryPanel, "Cell Warning Voltage")
    local warnField = form.addNumberField(warnLine, nil, 5, 600, function()
        return math.floor(tonumber(widget.vbatwarningcellvoltage) or 35)
    end, function(value)
        widget.vbatwarningcellvoltage = clamp(math.floor(tonumber(value) or 35), 5, 600)
        persistWidgetSettings(widget)
    end)
    if warnField then
        warnField:suffix("v")
        warnField:decimals(1)
    end

    local minLine = addLine(batteryPanel, "Cell Minimum Voltage")
    local minField = form.addNumberField(minLine, nil, 5, 600, function()
        return math.floor(tonumber(widget.vbatmincellvoltage) or 33)
    end, function(value)
        widget.vbatmincellvoltage = clamp(math.floor(tonumber(value) or 33), 5, 600)
        persistWidgetSettings(widget)
    end)
    if minField then
        minField:suffix("v")
        minField:decimals(1)
    end

    local maxLine = addLine(batteryPanel, "Cell Maximum Voltage")
    local maxField = form.addNumberField(maxLine, nil, 5, 600, function()
        return math.floor(tonumber(widget.vbatmaxcellvoltage) or 43)
    end, function(value)
        widget.vbatmaxcellvoltage = clamp(math.floor(tonumber(value) or 43), 5, 600)
        persistWidgetSettings(widget)
    end)
    if maxField then
        maxField:suffix("v")
        maxField:decimals(1)
    end

    local fullLine = addLine(batteryPanel, "Cell Full Voltage")
    local fullField = form.addNumberField(fullLine, nil, 5, 600, function()
        return math.floor(tonumber(widget.vbatfullcellvoltage) or 41)
    end, function(value)
        widget.vbatfullcellvoltage = clamp(math.floor(tonumber(value) or 41), 5, 600)
        persistWidgetSettings(widget)
    end)
    if fullField then
        fullField:suffix("v")
        fullField:decimals(1)
    end

    local reserveLine = addLine(batteryPanel, "Consumption Warning %")
    local reserveField = form.addNumberField(reserveLine, nil, 0, 100, function()
        return math.floor(tonumber(widget.consumptionWarningPercentage) or 30)
    end, function(value)
        widget.consumptionWarningPercentage = clamp(math.floor(tonumber(value) or 30), 0, 100)
        persistWidgetSettings(widget)
    end)
    if reserveField and reserveField.suffix then
        reserveField:suffix("%")
    end

    local scaleLine = addLine(batteryPanel, "@i18n(app.modules.model.consumption_scale)@")
    local scaleField = form.addNumberField(scaleLine, nil, 50, 200, function()
        return math.floor(tonumber(widget.consumptionScale) or 100)
    end, function(value)
        widget.consumptionScale = clamp(math.floor(tonumber(value) or 100), 50, 200)
        persistWidgetSettings(widget)
    end)
    if scaleField and scaleField.suffix then
        scaleField:suffix("%")
    end

    local triggersPanel = form.addExpansionPanel("Triggers")
    triggersPanel:open(false)

    local armLine = addLine(triggersPanel, "Arm Switch")
    form.addSwitchField(armLine, nil, function()
        return decodeSwitchSpec(widget.armswitch)
    end, function(newValue)
        widget.armswitch = encodeSwitchSource(newValue)
        persistWidgetSettings(widget)
    end)

    local throttleHoldLine = addLine(triggersPanel, "Throttle Hold Switch")
    form.addSwitchField(throttleHoldLine, nil, function()
        return decodeSwitchSpec(widget.throttleholdswitch)
    end, function(newValue)
        widget.throttleholdswitch = encodeSwitchSource(newValue)
        persistWidgetSettings(widget)
    end)

    local inflightModeLine = addLine(triggersPanel, "Inflight Detection")
    local inflightSwitchField
    local function refreshConfigureForm()
        if form and form.clear then
            form.clear()
            configui.configure(widget)
        elseif form and form.invalidate then
            form.invalidate()
        end
    end

    local function clearInflightSwitchDisplay()
        if inflightSwitchField and inflightSwitchField.value then
            pcall(function()
                inflightSwitchField:value(nil)
            end)
        end
    end

    local function updateInflightSwitchEnabled()
        if inflightSwitchField and inflightSwitchField.enable then
            inflightSwitchField:enable(not isInflightRpmMode(widget.inflightswitch))
        end
    end

    form.addChoiceField(inflightModeLine, nil, INFLIGHT_MODE_CHOICES, function()
        if isInflightRpmMode(widget.inflightswitch) then
            return 0  -- RPM-based
        else
            return 1  -- Switch-based
        end
    end, function(newValue)
        if newValue == 0 then
            -- Clear any selected switch and force RPM mode.
            widget.inflightswitch = "RPM"
            clearInflightSwitchDisplay()
        else
            -- Switch mode starts with no selected switch, shown as "---".
            widget.inflightswitch = false
            clearInflightSwitchDisplay()
        end
        persistWidgetSettings(widget)
        updateInflightSwitchEnabled()
        refreshConfigureForm()
    end)

    local inflightLine = addLine(triggersPanel, "Inflight Switch")
    inflightSwitchField = form.addSwitchField(inflightLine, nil, function()
        if isInflightRpmMode(widget.inflightswitch) or widget.inflightswitch == false then
            return nil  -- No switch configured
        end
        return decodeSwitchSpec(widget.inflightswitch)
    end, function(newValue)
        if newValue then
            widget.inflightswitch = encodeSwitchSource(newValue)
        else
            widget.inflightswitch = false
        end
        persistWidgetSettings(widget)
    end)
    updateInflightSwitchEnabled()

    local delayLine = addLine(triggersPanel, "Inflight Switch Delay")
    local delayField = form.addNumberField(delayLine, nil, 0, 120, function()
        return math.floor(tonumber(widget.inflightswitch_delay) or 10)
    end, function(value)
        widget.inflightswitch_delay = clamp(math.floor(tonumber(value) or 10), 0, 120)
        persistWidgetSettings(widget)
    end)
    if delayField and delayField.suffix then
        delayField:suffix("s")
    end
end

return configui
