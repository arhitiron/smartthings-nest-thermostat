-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local t_utils = require "integration_test.utils"
local Uint32 = require "st.matter.data_types.Uint32"

local thermostat = clusters.Thermostat.attributes
local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat-nostate-nobattery.yml"),
  manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
  endpoints = {{
    endpoint_id = 1,
    clusters = {{cluster_id = clusters.Thermostat.ID, cluster_type = "SERVER", feature_map = 1}},
    device_types = {{device_type_id = 0x0301, device_type_revision = 1}},
  }},
})

local function subscription(with_demand)
  local request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  for _, attribute in ipairs({
    thermostat.LocalTemperature, thermostat.OccupiedHeatingSetpoint, thermostat.OccupiedCoolingSetpoint,
    thermostat.AbsMinHeatSetpointLimit, thermostat.AbsMaxHeatSetpointLimit,
    thermostat.AbsMinCoolSetpointLimit, thermostat.AbsMaxCoolSetpointLimit,
    thermostat.SystemMode, thermostat.ControlSequenceOfOperation,
  }) do
    request:merge(attribute:subscribe(mock_device))
  end
  if with_demand then request:merge(thermostat.PIHeatingDemand:subscribe(mock_device)) end
  return request
end

test.set_test_init_function(function()
  test.socket.matter:__set_channel_ordering("relaxed")
  test.socket.matter:__expect_send({mock_device.id, subscription(false)})
  test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
  test.mock_device.add_test_device(mock_device)
end)

test.register_coroutine_test("Existing device init reads AttributeList without added", function()
  test.socket.matter:__expect_send({mock_device.id, thermostat.AttributeList:read(mock_device, 1)})
  test.mock_time.advance_time(5)
  test.wait_for_events()
end)

test.register_coroutine_test("Driver switch coalesces with init and can trigger a later diagnostic read", function()
  test.socket.device_lifecycle:__queue_receive({mock_device.id, "driverSwitched"})
  test.wait_for_events()
  test.socket.matter:__expect_send({mock_device.id, thermostat.AttributeList:read(mock_device, 1)})
  test.mock_time.advance_time(5)
  test.wait_for_events()
  test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
  test.socket.device_lifecycle:__queue_receive({mock_device.id, "driverSwitched"})
  test.wait_for_events()
  test.socket.matter:__expect_send({mock_device.id, thermostat.AttributeList:read(mock_device, 1)})
  test.mock_time.advance_time(5)
  test.wait_for_events()
end)

test.register_message_test("Absent heating demand does not request or subscribe to it", {{
  channel = "matter", direction = "receive",
  message = {mock_device.id, thermostat.AttributeList:build_test_report_data(mock_device, 1, {Uint32(0x0000), Uint32(0x0012), Uint32(0xFFFB)})},
}})

test.register_coroutine_test("Supported demand is read and merged with normal thermostat subscription once", function()
  local report = thermostat.AttributeList:build_test_report_data(mock_device, 1, {Uint32(0x0029), Uint32(0x0008), Uint32(0x0000), Uint32(0xFFFB)})
  test.socket.matter:__expect_send({mock_device.id, thermostat.PIHeatingDemand:read(mock_device, 1)})
  test.socket.matter:__expect_send({mock_device.id, subscription(true)})
  test.socket.matter:__queue_receive({mock_device.id, report})
  test.wait_for_events()
  test.socket.matter:__expect_send({mock_device.id, thermostat.PIHeatingDemand:read(mock_device, 1)})
  test.socket.matter:__queue_receive({mock_device.id, report})
  test.wait_for_events()
end)

test.register_message_test("Demand reports including zero leave normal heating setpoint events intact", {
  {channel = "matter", direction = "receive",
    message = {mock_device.id, thermostat.PIHeatingDemand:build_test_report_data(mock_device, 1, 0)}},
  {channel = "matter", direction = "receive",
    message = {mock_device.id, thermostat.PIHeatingDemand:build_test_report_data(mock_device, 1, 50)}},
  {channel = "matter", direction = "receive",
    message = {mock_device.id, thermostat.PIHeatingDemand:build_test_report_data(mock_device, 1, 0)}},
  {channel = "matter", direction = "receive",
    message = {mock_device.id, thermostat.OccupiedHeatingSetpoint:build_test_report_data(mock_device, 1, 2200)}},
  {channel = "capability", direction = "send",
    message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpointRange({value = {maximum = 100.0, minimum = 0.0, step = 0.1}, unit = "C"}))},
  {channel = "capability", direction = "send",
    message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 22.0, unit = "C"}))},
})

test.run_registered_tests()
