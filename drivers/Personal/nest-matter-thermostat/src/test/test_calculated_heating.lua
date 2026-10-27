-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local calculated = require "calculated_heating"

local function device_stub()
  local fields, events, timers, reads = {}, {}, {}, {}
  local device = {manufacturer_info = {vendor_id = 0x6006, product_id = 1}, log = {info = function() end}}
  function device:get_field(key) return fields[key] end
  function device:set_field(key, value) fields[key] = value end
  function device:supports_capability() return true end
  function device:emit_event_for_endpoint(endpoint, event)
    assert(endpoint == 1)
    events[#events + 1] = event.value.value
  end
  function device:send(request) reads[#reads + 1] = request end
  device.thread = {
    call_with_delay = function(_, _, callback) timers.startup = callback end,
    call_on_schedule = function(_, _, callback) timers.poll = callback end,
  }
  return device, events, timers, reads
end

local function report(device, id, value, endpoint)
  local called = false
  calculated.wrap(id, function() called = true end)(nil, device, {endpoint_id = endpoint or 1, data = {value = value}})
  return called
end

local function inputs(device, temperature, setpoint, mode)
  report(device, 0x0000, temperature)
  report(device, 0x0012, setpoint)
  report(device, 0x001C, mode or 4)
end

test.register_coroutine_test("Hysteresis holds demand until setpoint and suppresses duplicate events", function()
  local device, events = device_stub()
  inputs(device, 1950, 2000)
  assert(events[#events] == "heating")
  local count = #events
  report(device, 0x0000, 1999)
  assert(#events == count)
  report(device, 0x0000, 2000)
  assert(events[#events] == "idle")
  count = #events
  report(device, 0x0000, 1975)
  assert(#events == count)
  report(device, 0x0000, 1950)
  assert(events[#events] == "heating")
end)

test.register_coroutine_test("Physical 77 F and 68 F setpoints produce heating then idle at 23.01 C", function()
  local device, events = device_stub()
  inputs(device, 2301, 2000)
  assert(events[#events] == "idle")
  assert(report(device, 0x0012, 2500))
  assert(events[#events] == "heating")
  assert(report(device, 0x0012, 2000))
  assert(events[#events] == "idle")
end)

test.register_coroutine_test("Off and non-heat modes override demand immediately", function()
  local device, events = device_stub()
  inputs(device, 1800, 2000)
  assert(events[#events] == "heating")
  report(device, 0x001C, 0)
  assert(events[#events] == "idle")
  report(device, 0x001C, 4)
  assert(events[#events] == "heating")
  report(device, 0x001C, 3)
  assert(events[#events] == "idle")
end)

test.register_coroutine_test("No heating until all inputs arrive; null and invalid reports clear demand", function()
  local device, events = device_stub()
  report(device, 0x001C, 4)
  report(device, 0x0012, 2000)
  assert(events[#events] == "idle")
  report(device, 0x0000, 1800)
  assert(events[#events] == "heating")
  assert(not report(device, 0x0000, -32768))
  assert(events[#events] == "idle")
  report(device, 0x0000, 1800)
  assert(events[#events] == "heating")
  assert(not report(device, 0x0012, nil))
  assert(events[#events] == "idle")
end)

test.register_coroutine_test("Stale temperature expires even while setpoint and mode continue arriving", function()
  local device, events = device_stub()
  inputs(device, 1800, 2000)
  test.mock_time.advance_time(299)
  report(device, 0x0012, 2000)
  report(device, 0x001C, 4)
  assert(events[#events] == "heating")
  test.mock_time.advance_time(1)
  calculated.evaluate(device)
  assert(events[#events] == "idle")
  report(device, 0x0000, 1800)
  assert(events[#events] == "heating")
end)

test.register_coroutine_test("Restart requires fresh inputs and periodic reads recover stale state", function()
  local device, events, timers, reads = device_stub()
  inputs(device, 1800, 2000)
  assert(events[#events] == "heating")
  calculated.init(device)
  assert(events[#events] == "idle")
  timers.startup()
  assert(#reads == 1 and #reads[1].info_blocks == 3)
  for _, block in ipairs(reads[1].info_blocks) do
    assert(block.endpoint_id == 1 and block.cluster_id == 0x0201)
    assert(block.attribute_id == 0 or block.attribute_id == 0x0012 or block.attribute_id == 0x001C)
  end
  inputs(device, 1800, 2000)
  test.mock_time.advance_time(300)
  timers.poll()
  assert(events[#events] == "idle" and #reads == 2)
end)

test.register_coroutine_test("Other manufacturers and endpoints keep original handlers", function()
  local device, events = device_stub()
  device.manufacturer_info.vendor_id = 0
  assert(report(device, 0x0000, 1800))
  assert(#events == 0)
  device.manufacturer_info.vendor_id = 0x6006
  assert(report(device, 0x0000, 1800, 2))
  assert(#events == 0)
end)

test.run_registered_tests()
