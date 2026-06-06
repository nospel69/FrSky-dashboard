--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local dashx = require("FSDash")

local arg = {...}
local config = arg[1]

local telemetry = {}
local protocol, telemetrySOURCE, crsfSOURCE

local sensors = setmetatable({}, {__mode = "v"})

local cache_hits, cache_misses = 0, 0

local HOT_SIZE = 40
local hot_list, hot_index = {}, {}

local function mark_hot(key)
    local idx = hot_index[key]
    if idx then
        table.remove(hot_list, idx)
    elseif #hot_list >= HOT_SIZE then
        local old = table.remove(hot_list, 1)
        hot_index[old] = nil

        sensors[old] = nil
    end
    table.insert(hot_list, key)
    hot_index[key] = #hot_list
end

function telemetry._debugStats()
    local hot_count = #hot_list
    return {hits = cache_hits, misses = cache_misses, hot_size = hot_count, hot_list = hot_list}
end

local sensorRateLimit = os.clock()
local ONCHANGE_RATE = 0.5

local lastValidationResult = nil
local lastValidationTime = 0
local VALIDATION_RATE_LIMIT = 2

local lastCacheFlushTime = 0
local CACHE_FLUSH_INTERVAL = 5

local telemetryState = false

local lastSensorValues = {}

telemetry.sensorStats = {}

local filteredOnchangeSensors = nil
local onchangeInitialized = false

local sensorTable = {

    rssi = {   -- VFR  VFR2_4G   --VFR 900m   
        name = "@i18n(sensors.rssi)@",
        mandatory = true,
        stats = true,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {
            sim = {{appId = 0xF010, subId = 0}},
            sport = {
                    {appId = 0xF010, subId = 0},
                    {appId = 0xF010, subId = 0x18}
                    },
            crsf = {{crsfId = 0x14, subId = 2}},
            spektrum = {"Tx RSSI"}
        }
    },

    link = {  --rx - RSSI 2.4  rssi_900m
        name = "@i18n(sensors.link)@",
        mandatory = true,
        stats = true,
        switch_alerts = false,
        unit = UNIT_DB,
        unit_string = "dB",
        sensors = {
            sim = {{appId = 0xF101, subId = 0}},
            sport = {
                    {appId = 0xF101, subId = 0},
                    {appId = 0xF101, subId = 0x18},
                },
            crsf = {"Rx RSSI1"},
            spektrum = {"Tx RSSI"}
        }
    },

    voltage = {     --vfas in transmitter
        name = "@i18n(sensors.voltage)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 3,
        switch_alerts = true,
        unit = UNIT_VOLT,
        unit_string = "V",
        sensors = {
            sim = {{uid = 0x5002, unit = UNIT_VOLT, dec = 2, value = function() return dashx.utils.simSensors('voltage') end, min = 0, max = 3000}},
            sport = {
                    {appId = 0x0B50, subId = 0}, 
                    {appId = 0x0210, subId = 0}, 
                 --   {appId = 0xF103, subId = 0},    --ADC2 ?
                 --   {appId = 0xF103, subId = 1},
                    {appId = 0x021F, subId = 0x11}
                },
            crsf = {
                    {crsfId = 0x08, subId = 0},
                    "Rx Batt",
                    "RxBatt",
                    "VFAS"
                },
            spektrum = {"LiPo1", "LiPo2", "RxBatt"}
        }
    },

    rpm = {
        name = "@i18n(sensors.headspeed)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 60,
        switch_alerts = true,
        unit = UNIT_RPM,
        unit_string = "rpm",
        sensors = {
            sim = {{uid = 0x5003, unit = UNIT_RPM, dec = nil, value = function() return dashx.utils.simSensors('rpm') end, min = 0, max = 4000}}, 
            sport = {
                    {appId = 0x0B60, subId = 0}, 
                    {appId = 0x0500, subId = 0},
                    {appId = 0x050F, subId = 0x04}
                },
            crsf = {
                    {crsfId = 0x02, subId = 3},
                    "RPM",
                    "Headspeed"
                }
        }
    },

    fuel = {
        name = "@i18n(sensors.fuel)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 6,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {
            sim = {{uid = 0x5007, unit = UNIT_PERCENT, dec = 0, value = function() return dashx.utils.simSensors('fuel') end, min = 0, max = 100}}, 
            sport = {
                    {appId = 0x060F, subId = 0x12},
                    {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0600}
                    }, 
            crsf = {"Rx Batt%", "RxBatt%"}
        }
    },

    smartfuel = {
        name = "@i18n(sensors.smartfuel)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = nil,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {
            sim = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE1}}, 
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE1}}, 
            crsf = {
                    {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE1},
                    {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF}
                }
        }
    },

    smartconsumption = {
        name = "@i18n(sensors.smartconsumption)@",
        mandatory = false,
        stats = true,
        switch_alerts = true,
        unit = UNIT_MILLIAMPERE_HOUR,
        unit_string = "mAh",
        sensors = {
            sim = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDE}}, 
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDE}}, 
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDE}}
        }
    },

    current = {
        name = "@i18n(sensors.current)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 18,
        switch_alerts = true,
        unit = UNIT_AMPERE,
        unit_string = "A",
        sensors = {
            sim = {{uid = 0x5004, unit = UNIT_AMPERE, dec = 0, value = function() return dashx.utils.simSensors('current') end, min = 0, max = 300}}, 
            sport = {
                    {appId = 0x0B50, subId = 1}, 
                    {appId = 0x0200, subId = 0}, 
                    {appId = 0x020F, subId = 0x02}
            },
            crsf = {"Rx Current"},
            spektrum = {"ESC current"}
        }
    },

    temp_esc = {   -- temp1 in transmitter
        name = "@i18n(sensors.esc_temp)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 23,
        switch_alerts = true,
        unit = UNIT_DEGREE,
        sensors = {
            sim = {{uid = 0x5005, unit = UNIT_DEGREE, dec = 0, value = function() return dashx.utils.simSensors('temp_esc') end, min = 0, max = 100}}, 
            sport = {
                    {appId = 0x0B70, subId = 0},
                    {appId = 0x040F, subId = 0x0C}
                },
            spektrum = {"ESC temp"},
        },
        localizations = function(value)
            local major = UNIT_DEGREE
            if value == nil then return nil, major, nil end

            local prefs = dashx.preferences.localizations
            local isFahrenheit = prefs and prefs.temperature_unit == 1

            if isFahrenheit then return value * 1.8 + 32, major, "°F" end

            return value, major, "°C"
        end
    },

    altitude = {
        name = "@i18n(sensors.altitude)@",
        mandatory = false,
        stats = true,
        switch_alerts = true,
        unit = UNIT_METER,
        sensors = {
            sim = {{uid = 0x5016, unit = UNIT_METER, dec = 0, value = function() return dashx.utils.simSensors('altitude') end, min = 0, max = 50000}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0820}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0100}},
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x10B2}},
            crsfLegacy = {nil}
        },
        localizations = function(value)
            local major = UNIT_METER
            if value == nil then return nil, major, nil end
            local prefs = dashx.preferences.localizations
            local isFeet = prefs and prefs.altitude_unit == 1
            if isFeet then return value * 3.28084, major, "ft" end
            return value, major, "m"
        end
    },

    consumption = {
        name = "@i18n(sensors.consumption)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 5,
        switch_alerts = true,
        unit = UNIT_MILLIAMPERE_HOUR,
        unit_string = "mAh",
        sensors = {
            sim = {{uid = 0x5008, unit = UNIT_MILLIAMPERE_HOUR, dec = 0, value = function() return dashx.utils.simSensors('consumption') end, min = 0, max = 5000}}, 
            sport = {
                    {appId = 0x0B60, subId = 1}, 
                    {appId = 0x0B30, subId = 0},
                    {appId = 0x0B3F, subId = 0x0B}
                }, 
            crsf = {"Rx Cons"}}
    },

    armed = {
        name = "@i18n(sensors.arming_flags)@",
        mandatory = false,
        stats = false,
        set_telemetry_sensors = nil,
        switch_alerts = false,
        unit = UNIT_RAW,
        unit_string = nil,
        sensors = {
            sim = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE0}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE0}},
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE0}}
        }
    },

    inflight = {
        name = "@i18n(sensors.inflight)@",
        mandatory = false,
        stats = false,
        set_telemetry_sensors = nil,
        switch_alerts = false,
        unit = UNIT_RAW,
        unit_string = nil,
        sensors = {
            sim = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF}},
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF}}
        }
    },

    profile = {
        name = "@i18n(sensors.profile)@",
        mandatory = false,
        stats = false,
        set_telemetry_sensors = nil,
        switch_alerts = false,
        unit = UNIT_RAW,
        unit_string = nil,
        sensors = {
            sim = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FED}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FED}},
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FED}}
        }
    },

    accx = {
        name = "@i18n(sensors.accx)@",
        mandatory = false,
        stats = false,
        sensors = {
            sim = {{uid = 0x5019, unit = UNIT_G, dec = 3, value = function() return dashx.utils.simSensors('accx') end, min = -4000, max = 4000}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0700}},
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1111}},
            crsfLegacy = {nil}
        }
    },

    bec_voltage = {    --rxbatt in transmitter
        name = "@i18n(sensors.bec_voltage)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 43,
        switch_alerts = true,
        unit = UNIT_VOLT,
        unit_string = "V",
        sensors = {
            sim = {{uid = 0x5017, unit = UNIT_VOLT, dec = 2, value = function() return dashx.utils.simSensors('bec_voltage') end, min = 0, max = 3000}},
            sport = {
                    {appId = 0xF104, subId = 0x18},
                    {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0901}, 
                    {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0219}
                },
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1081}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1049}},
            crsfLegacy = {nil}
        }
    },

    accy = {
        name = "@i18n(sensors.accy)@",
        mandatory = false,
        stats = false,
        sensors = {
            sim = {{uid = 0x5020, unit = UNIT_G, dec = 3, value = function() return dashx.utils.simSensors('accy') end, min = -4000, max = 4000}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0710}},
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1112}},
            crsfLegacy = {nil}
        }
    },

    cell_count = {
        name = "@i18n(sensors.cell_count)@",
        mandatory = false,
        stats = false,
        sensors = {
            sim = {{uid = 0x5018, unit = nil, dec = 0, value = function() return dashx.utils.simSensors('cell_count') end, min = 0, max = 50}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5260}},
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1020}},
            crsfLegacy = {nil}
        }
    },

    accz = {
        name = "@i18n(sensors.accz)@",
        mandatory = false,
        stats = false,
        sensors = {
            sim = {{uid = 0x5021, unit = UNIT_G, dec = 3, value = function() return dashx.utils.simSensors('accz') end, min = -4000, max = 4000}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0720}},
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1113}},
            crsfLegacy = {nil}
        }
    },

    attyaw = {
        name = "@i18n(sensors.attyaw)@",
        mandatory = false,
        stats = false,
        sensors = {
            sim = {{uid = 0x5022, unit = UNIT_DEGREE, dec = 1, value = function() return dashx.utils.simSensors('attyaw') end, min = -1800, max = 3600}}, 
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5210}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0830}}, 
            crsf = {"Yaw"}
        }
    },

    attroll = {
        name = "@i18n(sensors.attroll)@",
        mandatory = false,
        stats = false,
        sensors = {
            sim = {{uid = 0x5023, unit = UNIT_DEGREE, dec = 1, value = function() return dashx.utils.simSensors('attroll') end, min = -1800, max = 3600}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0730, subId = 0}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0440, subId = 0}},
            crsf = {"Roll"}
        }
    },

    attpitch = {
        name = "@i18n(sensors.attpitch)@",
        mandatory = false,
        stats = false,
        sensors = {
            sim = {{uid = 0x5024, unit = UNIT_DEGREE, dec = 1, value = function() return dashx.utils.simSensors('attpitch') end, min = -1800, max = 3600}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0730, subId = 1}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0430, subId = 0}},
            crsf = {"Pitch"}
        }
    },

    transFlightMode = {
        name = "@i18n(sensors.flightmode)@",
        mandatory = false,
        stats = false,
        sensors = {
            sim = {
                    {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FEC},
                    {uid = 0x5024, unit = UNIT_DEGREE, dec = 1, value = function() return dashx.utils.simSensors('flightmode') end, min = -1800, max = 3600}
                },
            sport = {
                    {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FEC},
                    {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0730, subId = 1}
                },
            crsf = {
                    {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FEC},
                    "Flight mode"
                }}
    },

    groundspeed = {
        name = "@i18n(sensors.groundspeed)@",
        mandatory = false,
        stats = false,
        sensors = {
            sim = {{uid = 0x5025, unit = UNIT_KNOT, dec = 1, value = function() return dashx.utils.simSensors('groundspeed') end, min = -1800, max = 3600}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0830, subId = 0}},
            crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1128}},
            crsfLegacy = {nil}
        }
    },

    gps_sats = {
        name = "@i18n(sensors.gps_sats)@",
        mandatory = false,
        stats = false,
        sensors = {
            sim = {{uid = 0x5026, unit = UNIT_KNOT, dec = 0, value = function() return dashx.utils.simSensors('gps_sats') end, min = -1800, max = 3600}},
            sport = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0480, subId = 0}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0410, subId = 0}},
            crsfLegacy = {"GPS Sats"}
        }
    },

    -- Basic pass-through entries for additional named telemetry sources.
    -- These use string-based source lookup and are intended as starter mappings.
    ADC2 = {
        name = "@i18n(sensors.ADC2)@",
        mandatory = false,
        stats = false,
        unit = UNIT_RAW,
        sensors = {
            sport = {"ADC2"},
            crsf = {"ADC2"},
            spektrum = {"ADC2"}
        }
    },

    ADC2_4G = {
        name = "@i18n(sensors.ADC2.4G)@",
        mandatory = false,
        stats = false,
        unit = UNIT_RAW,
        sensors = {
            sport = {"ADC2.4G"},
            crsf = {"ADC2.4G"},
            spektrum = {"ADC2.4G"}
        }
    },

    adj_func = {
        name = "@i18n(sensors.adj_func)@",
        mandatory = false,
        stats = false,
        unit = UNIT_RAW,
        sensors = {
            sport = {"adj_func"},
            crsf = {"adj_func"},
            spektrum = {"adj_func"}
        }
    },

    adj_val = {
        name = "@i18n(sensors.adj_val)@",
        mandatory = false,
        stats = false,
        unit = UNIT_RAW,
        sensors = {
            sport = {"adj_val"},
            crsf = {"adj_val"},
            spektrum = {"adj_val"}
        }
    },

    armdisableflags = {
        name = "@i18n(sensors.armdisableflags)@",
        mandatory = false,
        stats = false,
        unit = UNIT_RAW,
        sensors = {
            sport = {"armdisableflags"},
            crsf = {"armdisableflags"},
            spektrum = {"armdisableflags"}
        }
    },



    Bat1cons = {
        name = "@i18n(sensors.Bat1cons)@",
        mandatory = false,
        stats = false,
        unit = UNIT_MILLIAMPERE_HOUR,
        unit_string = "mAh",
        sensors = {
            sport = {"Bat1cons"},
            crsf = {"Bat1cons"},
            spektrum = {"Bat1cons"}
        }
    },

    Bat2cons = {
        name = "@i18n(sensors.Bat2cons)@",
        mandatory = false,
        stats = false,
        unit = UNIT_MILLIAMPERE_HOUR,
        unit_string = "mAh",
        sensors = {
            sport = {"Bat2cons"},
            crsf = {"Bat2cons"},
            spektrum = {"Bat2cons"}
        }
    },

  

    GASS_res = {
        name = "@i18n(sensors.GASS_res)@",
        mandatory = false,
        stats = false,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {
            sport = {"GASS_res"},
            crsf = {"GASS_res"},
            spektrum = {"GASS_res"}
        }
    },

    governor = {
        name = "@i18n(sensors.governor)@",
        mandatory = false,
        stats = false,
        unit = UNIT_RAW,
        sensors = {
            sport = {"governor"},
            crsf = {"governor"},
            spektrum = {"governor"}
        }
    },

  
    mcu_temp = {
        name = "@i18n(sensors.mcu_temp)@",
        mandatory = false,
        stats = false,
        unit = UNIT_DEGREE,
        sensors = {
            sport = {"mcu_temp"},
            crsf = {"mcu_temp"},
            spektrum = {"mcu_temp"}
        }
    },

    Power900M = {
        name = "@i18n(sensors.Power900M)@",
        mandatory = false,
        stats = false,
        unit = UNIT_RAW,
        sensors = {
            sport = {"Power900M"},
            crsf = {"Power900M"},
            spektrum = {"Power900M"}
        }
    },

    rate_profile = {
        name = "@i18n(sensors.rate_profile)@",
        mandatory = false,
        stats = false,
        unit = UNIT_RAW,
        sensors = {
            sport = {"rate_profile"},
            crsf = {"rate_profile"},
            spektrum = {"rate_profile"}
        }
    },

    RSSI2_4G = {
        name = "@i18n(sensors.RSSI2_4G)@",
        mandatory = false,
        stats = false,
        unit = UNIT_DB,
        unit_string = "dB",
        sensors = {
            sport = {"RSSI2_4G"},
            crsf = {"RSSI2_4G"},
            spektrum = {"RSSI2_4G"}
        }
    },

    RSSI900M = {
        name = "@i18n(sensors.RSSI900M)@",
        mandatory = false,
        stats = false,
        unit = UNIT_DB,
        unit_string = "dB",
        sensors = {
            sport = {"RSSI900M"},
            crsf = {"RSSI900M"},
            spektrum = {"RSSI900M"}
        }
    },

    RX = {
        name = "@i18n(sensors.RX)@",
        mandatory = false,
        stats = false,
        unit = UNIT_RAW,
        sensors = {
            sport = {"RX"},
            crsf = {"RX"},
            spektrum = {"RX"}
        }
    },

    RxBatt = {
        name = "@i18n(sensors.RxBatt)@",
        mandatory = false,
        stats = false,
        unit = UNIT_VOLT,
        unit_string = "V",
        sensors = {
            sport = {"RxBatt"},
            crsf = {"RxBatt"},
            spektrum = {"RxBatt"}
        }
    },

    RxVFR = {
        name = "@i18n(sensors.RxVFR)@",
        mandatory = false,
        stats = false,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {
            sport = {"RxVFR"},
            crsf = {"RxVFR"},
            spektrum = {"RxVFR"}
        }
    },

    temp1 = {
        name = "@i18n(sensors.temp1)@",
        mandatory = false,
        stats = false,
        unit = UNIT_DEGREE,
        sensors = {
            sport = {"temp1"},
            crsf = {"temp1"},
            spektrum = {"temp1"}
        }
    },

    throttle_pct = {
        name = "@i18n(sensors.throttle_pct)@",
        mandatory = false,
        stats = false,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {
            sport = {"throttle_pct"},
            crsf = {"throttle_pct"},
            spektrum = {"throttle_pct"}
        }
    },

    VFAS = {
        name = "@i18n(sensors.VFAS)@",
        mandatory = false,
        stats = false,
        unit = UNIT_VOLT,
        unit_string = "V",
        sensors = {
            sport = {"VFAS"},
            crsf = {"VFAS"},
            spektrum = {"VFAS"}
        }
    },

    VFR2_4G = {
        name = "@i18n(sensors.VFR2_4G)@",
        mandatory = false,
        stats = false,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {
            sport = {"VFR2_4G"},
            crsf = {"VFR2_4G"},
            spektrum = {"VFR2_4G"}
        }
    },

    VFR900M = {
        name = "@i18n(sensors.VFR900M)@",
        mandatory = false,
        stats = false,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {
            sport = {"VFR900M"},
            crsf = {"VFR900M"},
            spektrum = {"VFR900M"}
        }
    }

}

local sportPhase1Resolver = {
    voltage = {
        names = {"VFAS", "vfas", "voltage", "batv", "battery"},
        range = {min = 0, max = 100}
    },
    rxbatt = {
        names = {"RxBatt", "rx batt", "bec voltage", "bec volt", "becv"},
        range = {min = 2, max = 12.6}
    },
    rpm = {
        names = {"RPM", "headspeed", "headspeed", "rotor"},
        range = {min = 0, max = 25000}
    },
    current = {
        names = {"Current", "esc current", "rx current", "curr"},
        range = {min = 0, max = 600}
    },
    consumption = {
        names = {"consumption", "Bat1cons.", "cons", "mah", "capacity", "rx cons", "bat1cons", "bat2cons"},
        range = {min = 0, max = 10000}
    }
}

local function safeMethodCall(source, methodName)
    if not source then
        return nil
    end

    local fn = source[methodName]
    if type(fn) ~= "function" then
        return nil
    end

    local ok, value = pcall(fn, source)
    if not ok then
        return nil
    end

    return value
end

local function normalizeLookupText(value)
    if value == nil then
        return ""
    end

    return tostring(value):lower():gsub("[%s_%-]+", "")   -- removes spaces, underscores, and dashes for more flexible matching
end

local function isPhase1SportKey(sensorKey)
    return sportPhase1Resolver[sensorKey] ~= nil
end

local sportResolvedBindings = {}

local function cloneQuery(query)
    if type(query) ~= "table" then
        return query
    end

    local copy = {}
    for k, v in pairs(query) do
        copy[k] = v
    end
    return copy
end

local function getModelBindingKey()
    local path = model and model.path and model.path() or ""
    local name = model and model.name and model.name() or ""
    local raw = path ~= "" and path or name

    if dashx and dashx.utils and dashx.utils.sanitize_filename then
        return dashx.utils.sanitize_filename(raw) or "default"
    end

    return raw ~= "" and raw or "default"
end

local function getSavedSportBinding(sensorKey)
    local modelKey = getModelBindingKey()
    local modelBindings = sportResolvedBindings[modelKey]
    local binding = modelBindings and modelBindings[sensorKey] or nil
    if not binding then
        return nil
    end

    local source = system.getSource(binding.query)
    if not source then
        modelBindings[sensorKey] = nil
        return nil
    end

    local expectedUnit = sensorTable[sensorKey] and sensorTable[sensorKey].unit or nil
    local sourceUnit = safeMethodCall(source, "unit")
    if expectedUnit ~= nil and sourceUnit ~= nil and expectedUnit ~= sourceUnit then
        modelBindings[sensorKey] = nil
        return nil
    end

    local state = safeMethodCall(source, "state")
    if state == false then
        modelBindings[sensorKey] = nil
        return nil
    end

    print("[DEBUG] telemetry.resolveSportSource: cache hit key=" .. sensorKey .. " model=" .. modelKey)
    return source
end

local function saveSportBinding(sensorKey, query, score)
    if query == nil then
        return
    end

    local modelKey = getModelBindingKey()
    sportResolvedBindings[modelKey] = sportResolvedBindings[modelKey] or {}
    sportResolvedBindings[modelKey][sensorKey] = {
        query = cloneQuery(query),
        score = score,
        savedAt = os.clock()
    }
end

local function scoreSportCandidate(sensorKey, source, queryMeta)
    local profile = sportPhase1Resolver[sensorKey]
    if not profile then
        return -math.huge
    end

    local score = 0
    local nameScore = 0
    local unitScore = 0

    local sourceName = safeMethodCall(source, "name")
    local normalizedName = normalizeLookupText(sourceName)

    local expectedUnit = sensorTable[sensorKey] and sensorTable[sensorKey].unit or nil
    local sourceUnit = safeMethodCall(source, "unit")

    if expectedUnit ~= nil and sourceUnit ~= nil then
        if expectedUnit == sourceUnit then
            unitScore = 40
        else
            unitScore = -20
        end
    end

    for _, alias in ipairs(profile.names or {}) do
        local normalizedAlias = normalizeLookupText(alias)
        if normalizedAlias ~= "" then
            if normalizedName == normalizedAlias then
                nameScore = math.max(nameScore, 40)
            elseif normalizedName:find(normalizedAlias, 1, true) then
                nameScore = math.max(nameScore, 24)
            end
        end
    end

    local value = safeMethodCall(source, "value")
    if type(value) == "number" then
        local range = profile.range
        if range and value >= range.min and value <= range.max then
            score = score + 10
        else
            score = score - 10
        end
    end

    local state = safeMethodCall(source, "state")
    if state == nil or state ~= false then
        score = score + 5
    end

    if queryMeta and queryMeta.kind == "configured" then
        score = score + 3
    elseif queryMeta and queryMeta.kind == "alias" then
        score = score + 5
    end

    score = score + nameScore + unitScore
    return score, nameScore, unitScore, sourceName, sourceUnit
end

local function resolveSportSourcePhase1(sensorKey)
    if not isPhase1SportKey(sensorKey) then
        return nil
    end

    local savedSource = getSavedSportBinding(sensorKey)
    if savedSource then
        return savedSource
    end

    local sportSensors = sensorTable[sensorKey] and sensorTable[sensorKey].sensors and sensorTable[sensorKey].sensors.sport or {}
    local profile = sportPhase1Resolver[sensorKey]
    local candidates = {}
    local seen = {}

    local function pushCandidate(query, meta)
        local source = system.getSource(query)
        if not source or seen[source] then
            return
        end
        seen[source] = true
        candidates[#candidates + 1] = {source = source, meta = meta}
    end

    local function addCandidate(query, meta)
        pushCandidate(query, meta)

        if type(query) == "string" then
            local lower = string.lower(query)
            local upper = string.upper(query)
            if lower ~= query then
                pushCandidate(lower, meta)
            end
            if upper ~= query then
                pushCandidate(upper, meta)
            end
        end
    end

    for _, query in ipairs(sportSensors) do
        addCandidate(query, {kind = "configured", query = query})
    end

    for _, alias in ipairs(profile.names or {}) do
        addCandidate(alias, {kind = "alias", query = alias})
    end

    local bestCandidate = nil
    for _, candidate in ipairs(candidates) do
        local score, nameScore, unitScore, sourceName, sourceUnit = scoreSportCandidate(sensorKey, candidate.source, candidate.meta)
        if score > -math.huge then
            print(
                "[DEBUG] telemetry.resolveSportSource: candidate key=" .. sensorKey ..
                    " score=" .. tostring(score) ..
                    " nameScore=" .. tostring(nameScore) ..
                    " unitScore=" .. tostring(unitScore) ..
                    " name=" .. tostring(sourceName) ..
                    " unit=" .. tostring(sourceUnit)
            )

            if not bestCandidate or score > bestCandidate.score then
                bestCandidate = {source = candidate.source, score = score, query = candidate.meta and candidate.meta.query or nil}
            end
        end
    end

    if bestCandidate and bestCandidate.score >= 30 then
        saveSportBinding(sensorKey, bestCandidate.query, bestCandidate.score)
        print(
            "[DEBUG] telemetry.resolveSportSource: selected key=" .. sensorKey ..
                " score=" .. tostring(bestCandidate.score)
        )
        return bestCandidate.source
    end

    print("[DEBUG] telemetry.resolveSportSource: no confident match for key=" .. sensorKey)
    return nil
end

function telemetry.getSensorProtocol() return protocol end

function telemetry.listSensors()
    local sensorList = {}
    for key, sensor in pairs(sensorTable) do table.insert(sensorList, {key = key, name = sensor.name, mandatory = sensor.mandatory, set_telemetry_sensors = sensor.set_telemetry_sensors}) end
    return sensorList
end

function telemetry.listSensorAudioUnits()
    local sensorMap = {}
    for key, sensor in pairs(sensorTable) do if sensor.unit then sensorMap[key] = sensor.unit end end
    return sensorMap
end

function telemetry.listSwitchSensors()
    local sensorList = {}
    for key, sensor in pairs(sensorTable) do if sensor.switch_alerts then table.insert(sensorList, {key = key, name = sensor.name, mandatory = sensor.mandatory, set_telemetry_sensors = sensor.set_telemetry_sensors}) end end
    return sensorList
end

function telemetry.getSensorSource(name)
    if not sensorTable[name] then 
        print("[DEBUG] telemetry.getSensorSource: sensorTable['" .. tostring(name) .. "'] does not exist")
        return nil 
    end

    if sensors[name] then
        cache_hits = cache_hits + 1
        mark_hot(name)
        print("[DEBUG] telemetry.getSensorSource: cache HIT for '" .. name .. "'")
        return sensors[name]
    end

    local function checkCondition(sensorEntry)
        if not (dashx.session and dashx.session.apiVersion) then return true end
        local roundedApiVersion = dashx.utils.round(dashx.session.apiVersion, 2)
        if sensorEntry.mspgt then
            return roundedApiVersion >= dashx.utils.round(sensorEntry.mspgt, 2)
        elseif sensorEntry.msplt then
            return roundedApiVersion <= dashx.utils.round(sensorEntry.msplt, 2)
        end
        return true
    end

    if system.getVersion().simulation == true then
        protocol = "sport"
        print("[DEBUG] telemetry.getSensorSource: trying protocol 'sim' for '" .. name .. "'")
        for _, sensor in ipairs(sensorTable[name].sensors.sim or {}) do

            if sensor.uid then
                if sensor and type(sensor) == "table" then
                    local sensorQ = {appId = sensor.uid, category = CATEGORY_TELEMETRY_SENSOR}
                    local source = system.getSource(sensorQ)
                    if source then
                        cache_misses = cache_misses + 1
                        sensors[name] = source
                        mark_hot(name)
                        print("[DEBUG] telemetry.getSensorSource: RESOLVED '" .. name .. "' via sim (uid) with uid=" .. string.format("0x%04X", sensor.uid))
                        return source
                    end
                end
            else

                if checkCondition(sensor) and type(sensor) == "table" then
                    sensor.mspgt = nil
                    sensor.msplt = nil
                    local source = system.getSource(sensor)
                    if source then
                        cache_misses = cache_misses + 1
                        sensors[name] = source
                        mark_hot(name)
                        print("[DEBUG] telemetry.getSensorSource: RESOLVED '" .. name .. "' via sim (category) with appId=" .. string.format("0x%04X", sensor.appId or 0))
                        return source
                    end
                end
            end
        end
        print("[DEBUG] telemetry.getSensorSource: FAILED to resolve '" .. name .. "' via sim")
    elseif dashx.session.telemetryType == "crsf" then
        protocol = "crsf"
        print("[DEBUG] telemetry.getSensorSource: trying protocol 'crsf' for '" .. name .. "'")
        for _, sensor in ipairs(sensorTable[name].sensors.crsf or {}) do
            local source = system.getSource(sensor)
            if source then
                cache_misses = cache_misses + 1
                sensors[name] = source
                mark_hot(name)
                print("[DEBUG] telemetry.getSensorSource: RESOLVED '" .. name .. "' via crsf with sensor=" .. tostring(sensor))
                return source
            end
        end
        print("[DEBUG] telemetry.getSensorSource: FAILED to resolve '" .. name .. "' via crsf")
    elseif dashx.session.telemetryType == "sport" then
        protocol = "sport"
        print("[DEBUG] telemetry.getSensorSource: trying protocol 'sport' for '" .. name .. "'")

        local resolvedSportSource = resolveSportSourcePhase1(name)
        if resolvedSportSource then
            cache_misses = cache_misses + 1
            sensors[name] = resolvedSportSource
            mark_hot(name)
            print("[DEBUG] telemetry.getSensorSource: RESOLVED '" .. name .. "' via sport phase1 resolver")
            return resolvedSportSource
        end

        for _, sensor in ipairs(sensorTable[name].sensors.sport or {}) do
            local source = system.getSource(sensor)
            if source then
                cache_misses = cache_misses + 1
                sensors[name] = source
                mark_hot(name)
                print("[DEBUG] telemetry.getSensorSource: RESOLVED '" .. name .. "' via sport with appId=" .. string.format("0x%04X", sensor.appId or 0) .. ", subId=" .. (sensor.subId or 0))
                return source
            end
        end
        print("[DEBUG] telemetry.getSensorSource: FAILED to resolve '" .. name .. "' via sport")
    elseif dashx.session.telemetryType == "spektrum" then
        protocol = "spektrum"
        print("[DEBUG] telemetry.getSensorSource: trying protocol 'spektrum' for '" .. name .. "'")
        for _, sensor in ipairs(sensorTable[name].sensors.spektrum or {}) do
            local source = system.getSource(sensor)
            if source then
                cache_misses = cache_misses + 1
                sensors[name] = source
                mark_hot(name)
                print("[DEBUG] telemetry.getSensorSource: RESOLVED '" .. name .. "' via spektrum with sensor=" .. tostring(sensor))
                return source
            end
        end
        print("[DEBUG] telemetry.getSensorSource: FAILED to resolve '" .. name .. "' via spektrum")
    else
        protocol = "unknown"
        print("[DEBUG] telemetry.getSensorSource: UNKNOWN telemetry type for '" .. name .. "': telemetryType=" .. tostring(dashx.session.telemetryType))
    end

    print("[DEBUG] telemetry.getSensorSource: COMPLETE FAILURE - could not resolve '" .. name .. "' via any protocol")
    return nil
end

function telemetry.getSensor(sensorKey)
    local entry = sensorTable[sensorKey]
    local simEntry = entry and entry.sensors and entry.sensors.sim and entry.sensors.sim[1] or nil

    if system.getVersion().simulation == true and simEntry and type(simEntry.value) == "function" then
        local value = simEntry.value()
        local major = entry and entry.unit or simEntry.unit or nil
        local minor = nil

        if entry and entry.localizations and type(entry.localizations) == "function" then value, major, minor = entry.localizations(value) end

        return value, major, minor
    end

    if entry and type(entry.source) == "function" then
        local src = entry.source()
        if src and type(src.value) == "function" then
            local value, major, minor = src.value()
            major = major or entry.unit

            if entry.localizations and type(entry.localizations) == "function" then value, major, minor = entry.localizations(value) end
            return value, major, minor
        end
    end

    local source = telemetry.getSensorSource(sensorKey)
    if not source then return nil end

    local value = source:value()
    local major = entry and entry.unit or nil
    local minor = nil

    if entry and entry.localizations and type(entry.localizations) == "function" then value, major, minor = entry.localizations(value) end

    return value, major, minor
end

function telemetry.validateSensors(returnValid)
    local now = os.clock()
    if (now - lastValidationTime) < VALIDATION_RATE_LIMIT then return lastValidationResult end
    lastValidationTime = now

    if not dashx.session.telemetryState then
        local allSensors = {}
        for key, sensor in pairs(sensorTable) do table.insert(allSensors, {key = key, name = sensor.name}) end
        lastValidationResult = allSensors
        return allSensors
    end

    local resultSensors = {}
    for key, sensor in pairs(sensorTable) do
        local sensorSource = telemetry.getSensorSource(key)
        local isValid = (sensorSource ~= nil and sensorSource:state() ~= false)
        if returnValid then
            if isValid then table.insert(resultSensors, {key = key, name = sensor.name}) end
        else
            if not isValid and sensor.mandatory ~= false then table.insert(resultSensors, {key = key, name = sensor.name}) end
        end
    end

    lastValidationResult = resultSensors
    return resultSensors
end

function telemetry.simSensors(returnValid)
    local result = {}
    for key, sensor in pairs(sensorTable) do
        local name = sensor.name
        local firstSportSensor = sensor.sensors.sim and sensor.sensors.sim[1]
        if firstSportSensor then table.insert(result, {name = name, sensor = firstSportSensor}) end
    end
    return result
end

function telemetry.active() return dashx.session.telemetryState or false end

function telemetry.reset()
    telemetrySOURCE, crsfSOURCE, protocol = nil, nil, nil
    sensors = {}
    hot_list, hot_index = {}, {}

    filteredOnchangeSensors = nil
    lastSensorValues = {}
    onchangeInitialized = false
end

function telemetry.wakeup()
    local now = os.clock()

    if (now - sensorRateLimit) >= ONCHANGE_RATE then
        sensorRateLimit = now

        if not filteredOnchangeSensors then
            filteredOnchangeSensors = {}
            for sensorKey, sensorDef in pairs(sensorTable) do if type(sensorDef.onchange) == "function" then filteredOnchangeSensors[sensorKey] = sensorDef end end

            onchangeInitialized = true
        end

        if onchangeInitialized then
            onchangeInitialized = false
        else

            for sensorKey, sensorDef in pairs(filteredOnchangeSensors) do
                local source = telemetry.getSensorSource(sensorKey)
                if source and source:state() then
                    local val = source:value()
                    if lastSensorValues[sensorKey] ~= val then

                        sensorDef.onchange(val)
                        lastSensorValues[sensorKey] = val
                    end
                end
            end
        end
    end

    if not dashx.session.telemetryState or dashx.session.telemetryTypeChanged then telemetry.reset() end
end

function telemetry.getSensorStats(sensorKey) return telemetry.sensorStats[sensorKey] or {min = nil, max = nil} end

telemetry.sensorTable = sensorTable

return telemetry
