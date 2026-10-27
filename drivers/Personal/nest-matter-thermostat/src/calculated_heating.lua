-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local version = require "version"

local calculated = {}
local CACHE = "calculated_heating_inputs"
local HYSTERESIS = 50 -- Matter temperatures are hundredths of a degree Celsius.
local STALE_SECONDS = 300
local POLL_SECONDS = 60
local INPUTS = {0x0000, 0x0012, 0x001C}

function calculated.prepare(device)
  if not calculated.applies(device) or device:get_field("calculated_heating_subscription_filter") then return end
  local original = device.add_subscribed_attribute
  device:extend_device("add_subscribed_attribute", function(self, attr, opts)
    local cluster = attr.cluster or attr._cluster.ID
    local id = attr.ID or attr.attribute
    if cluster ~= clusters.Thermostat.ID or id ~= 0x0029 then original(self, attr, opts) end
  end)
  device:set_field("calculated_heating_subscription_filter", true)
end

function calculated.applies(device)
  local info = device.manufacturer_info or {}
  return info.vendor_id == 0x6006 and info.product_id == 0x0001 and version.api >= 15 and version.rpc >= 9
end

function calculated.evaluate(device)
  if not calculated.applies(device) then return end
  local cache = device:get_field(CACHE) or {values = {}, times = {}}
  local now = os.time()
  local fresh = true
  for _, id in ipairs(INPUTS) do
    if cache.values[id] == nil or cache.times[id] == nil or now - cache.times[id] >= STALE_SECONDS then
      fresh = false
    end
  end
  local state = "idle"
  if fresh and cache.values[0x001C] == clusters.Thermostat.types.ThermostatSystemMode.HEAT then
    local temperature, setpoint = cache.values[0x0000], cache.values[0x0012]
    if temperature <= setpoint - HYSTERESIS or (cache.state == "heating" and temperature < setpoint) then
      state = "heating"
    end
  end
  cache.state = state
  if device:supports_capability(capabilities.thermostatOperatingState) and cache.emitted ~= state then
    device:emit_event_for_endpoint(1, capabilities.thermostatOperatingState.thermostatOperatingState(state))
    device.log.info(string.format("CALCULATED_HEATING state=%s fresh=%s temperature=%s setpoint=%s mode=%s",
      state, tostring(fresh), tostring(cache.values[0x0000]), tostring(cache.values[0x0012]), tostring(cache.values[0x001C])))
    cache.emitted = state
  end
  device:set_field(CACHE, cache)
end

function calculated.wrap(attribute_id, original)
  return function(driver, device, ib, response)
    if not calculated.applies(device) or ib.endpoint_id ~= 1 then
      return original(driver, device, ib, response)
    end
    local cache = device:get_field(CACHE) or {values = {}, times = {}}
    local value = ib.data and ib.data.value
    local valid = type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    if attribute_id ~= 0x001C then valid = valid and value >= -27315 and value <= 32767 end
    cache.values[attribute_id] = valid and value or nil
    cache.times[attribute_id] = valid and os.time() or nil
    device:set_field(CACHE, cache)
    -- Invalid/null temperatures must not become an apparently valid capability value.
    if valid then original(driver, device, ib, response) end
    calculated.evaluate(device)
  end
end

function calculated.read_inputs(device)
  local request = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  for _, id in ipairs(INPUTS) do
    request:with_info_block(im.InteractionInfoBlock(1, clusters.Thermostat.ID, id))
  end
  device:send(request)
end

function calculated.init(device)
  if not calculated.applies(device) then return end
  -- Require fresh Matter reports after restart; never resume from a cached
  -- SmartThings heating state whose inputs might predate the restart.
  device:set_field(CACHE, {values = {}, times = {}})
  calculated.evaluate(device)
  device.thread:call_with_delay(5, function() calculated.read_inputs(device) end, "calculated heating startup read")
  device.thread:call_on_schedule(POLL_SECONDS, function()
    calculated.evaluate(device)
    calculated.read_inputs(device)
  end, "calculated heating refresh")
end

return calculated
