-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"

local diagnostics = {}
local PENDING = "thermostat_diag_pending"
local DEMAND = "thermostat_diag_demand"
local SUBSCRIBED = "thermostat_diag_subscribed"
local HEATING_DEMAND_ID = 0x0008
local RUNNING_STATE_ID = 0x0029

local function read_attribute(device, endpoint, attribute)
  local request = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  request:with_info_block(im.InteractionInfoBlock(endpoint, clusters.Thermostat.ID, attribute))
  device:send(request)
end

function diagnostics.read_attribute_lists(device)
  for _, endpoint in ipairs(device:get_endpoints(clusters.Thermostat.ID)) do
    device.log.info(string.format("THERMOSTAT_DIAG endpoint=%d reading AttributeList(0xFFFB)", endpoint))
    read_attribute(device, endpoint, 0xFFFB)
  end
end

-- Both init and driverSwitched may run during a switch; coalesce their reads.
function diagnostics.schedule(device)
  if device:get_field(PENDING) then return end
  device:set_field(PENDING, true)
  device.thread:call_with_delay(5, function()
    device:set_field(PENDING, false)
    diagnostics.read_attribute_lists(device)
  end, "thermostat diagnostic read")
end

function diagnostics.refresh(_, device)
  device:refresh()
  diagnostics.read_attribute_lists(device)
end

function diagnostics.attribute_list_handler(original_handler)
  return function(driver, device, ib, response)
    if not ib.data or not ib.data.elements then
      device.log.warn(string.format("THERMOSTAT_DIAG endpoint=%s AttributeList unavailable: %s", ib.endpoint_id, tostring(ib)))
      return
    end
    local ids, supported = {}, {}
    for _, attr in ipairs(ib.data.elements) do
      ids[#ids + 1] = attr.value
      supported[attr.value] = true
    end
    table.sort(ids)
    device.log.info(string.format("THERMOSTAT_DIAG endpoint=%d AttributeList count=%d BEGIN", ib.endpoint_id, #ids))
    -- One entry per line avoids truncating a long AttributeList in hub logcat.
    for index, id in ipairs(ids) do
      device.log.info(string.format("THERMOSTAT_DIAG endpoint=%d AttributeList[%d]=0x%04X", ib.endpoint_id, index, id))
    end
    device.log.info(string.format(
      "THERMOSTAT_DIAG endpoint=%d AttributeList END PIHeatingDemand(0x0008)=%s ThermostatRunningState(0x0029)=%s AttributeList(0xFFFB)=%s",
      ib.endpoint_id, supported[HEATING_DEMAND_ID] and "present" or "absent",
      supported[RUNNING_STATE_ID] and "present" or "absent", supported[0xFFFB] and "present" or "absent"))

    original_handler(driver, device, ib, response)

    if supported[HEATING_DEMAND_ID] then
      read_attribute(device, ib.endpoint_id, HEATING_DEMAND_ID)
      if not device:get_field(SUBSCRIBED) then
        -- The SDK uses a wildcard endpoint. Merge into its normal subscription
        -- so setpoint, mode, temperature, and all other reports remain active.
        device:add_subscribed_attribute({cluster = clusters.Thermostat.ID, attribute = HEATING_DEMAND_ID})
        device:subscribe()
        device:set_field(SUBSCRIBED, true)
        device.log.info("THERMOSTAT_DIAG PIHeatingDemand added to normal subscription request")
      end
    end
  end
end

function diagnostics.heating_demand_handler(_, device, ib)
  if not ib.data or type(ib.data.value) ~= "number" then
    device.log.warn(string.format("THERMOSTAT_DIAG endpoint=%s PIHeatingDemand unavailable: %s", ib.endpoint_id, tostring(ib)))
    return
  end
  local values = device:get_field(DEMAND) or {}
  local previous = values[ib.endpoint_id]
  local value = ib.data.value
  device.log.info(string.format("THERMOSTAT_DIAG endpoint=%d PIHeatingDemand raw=%s previous=%s transition=%s",
    ib.endpoint_id, tostring(value), tostring(previous), previous == nil and "initial" or
      (previous == value and "unchanged" or "changed")))
  values[ib.endpoint_id] = value
  device:set_field(DEMAND, values)
end

-- Non-success attribute responses bypass the SDK attribute handlers.
function diagnostics.unhandled_response(_, device, response_block)
  local ib = response_block.info_block
  if ib and ib.cluster_id == clusters.Thermostat.ID and
      (ib.attribute_id == HEATING_DEMAND_ID or ib.attribute_id == RUNNING_STATE_ID or ib.attribute_id == 0xFFFB) then
    device.log.warn(string.format("THERMOSTAT_DIAG endpoint=%s attribute=0x%04X unhandled status=%s data=%s",
      tostring(ib.endpoint_id), ib.attribute_id, tostring(response_block.status), tostring(ib.data)))
  end
end

return diagnostics
