-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local t_utils = require "integration_test.utils"
local attributes = clusters.Thermostat.attributes
local optional = {{"main", {"thermostatHeatingSetpoint", "thermostatOperatingState"}}}
local device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat-modular.yml", {enabled_optional_capabilities = optional}),
  manufacturer_info = {vendor_id = 0x6006, product_id = 1},
  endpoints = {{
    endpoint_id = 1,
    clusters = {{cluster_id = clusters.Thermostat.ID, cluster_type = "SERVER", feature_map = 1}},
    device_types = {{device_type_id = 0x0301, device_type_revision = 1}},
  }},
})

test.set_test_init_function(function()
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscription = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  for _, attr in ipairs({attributes.LocalTemperature, attributes.OccupiedHeatingSetpoint,
      attributes.AbsMinHeatSetpointLimit, attributes.AbsMaxHeatSetpointLimit,
      attributes.SystemMode, attributes.ControlSequenceOfOperation}) do
    subscription:merge(attr:subscribe(device))
  end
  -- No ThermostatRunningState path is expected despite enabling the capability.
  test.socket.matter:__expect_send({device.id, subscription})
  test.socket.capability:__expect_send(device:generate_test_message("main",
    capabilities.thermostatOperatingState.supportedThermostatOperatingStates({"idle", "heating"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(device:generate_test_message("main",
    capabilities.thermostatOperatingState.thermostatOperatingState.idle()))
  test.mock_device.add_test_device(device)
end)

test.register_message_test("Nest raw reports preserve temperature and setpoint events and add calculated heating and idle", {
  {channel = "matter", direction = "receive",
    message = {device.id, attributes.SystemMode:build_test_report_data(device, 1, 4)}},
  {channel = "matter", direction = "receive",
    message = {device.id, attributes.LocalTemperature:build_test_report_data(device, 1, 2301)}},
  {channel = "capability", direction = "send", message = device:generate_test_message("main",
    capabilities.temperatureMeasurement.temperature({value = 23.01, unit = "C"}))},
  {channel = "matter", direction = "receive",
    message = {device.id, attributes.OccupiedHeatingSetpoint:build_test_report_data(device, 1, 2500)}},
  {channel = "capability", direction = "send", message = device:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpointRange({value = {minimum = 0.0, maximum = 100.0, step = 0.1}, unit = "C"}))},
  {channel = "capability", direction = "send", message = device:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 25.0, unit = "C"}))},
  {channel = "capability", direction = "send", message = device:generate_test_message("main",
    capabilities.thermostatOperatingState.thermostatOperatingState.heating())},
  {channel = "matter", direction = "receive",
    message = {device.id, attributes.OccupiedHeatingSetpoint:build_test_report_data(device, 1, 2000)}},
  {channel = "capability", direction = "send", message = device:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpointRange({value = {minimum = 0.0, maximum = 100.0, step = 0.1}, unit = "C"}))},
  {channel = "capability", direction = "send", message = device:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 20.0, unit = "C"}))},
  {channel = "capability", direction = "send", message = device:generate_test_message("main",
    capabilities.thermostatOperatingState.thermostatOperatingState.idle())},
})

test.register_coroutine_test("Driver switching selects modular heating and calculated state without native support", function()
  device:expect_metadata_update({profile = "thermostat-modular", optional_component_capabilities = optional})
  test.socket.device_lifecycle:__queue_receive({device.id, "driverSwitched"})
  test.wait_for_events()
end)

test.register_message_test("Native running-state report cannot overwrite calculated state", {{
  channel = "matter", direction = "receive",
  message = {device.id, attributes.ThermostatRunningState:build_test_report_data(device, 1, 1)},
}})

test.run_registered_tests()
