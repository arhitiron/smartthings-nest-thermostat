# SmartThings Nest Thermostat — calculated operating state

A SmartThings Edge driver for the **Google Nest Thermostat (2020)** paired
through Matter. It publishes calculated **heating / idle** status using the
standard `thermostatOperatingState` capability, so SmartThings routines can
control a separate dry-contact relay such as a Zooz ZEN17.

The Nest remains the physical temperature and setpoint interface. Calculation
runs locally on the hub; no Home Assistant or external server is required for
runtime operation. Installing the driver does not create routines or control
any relay. Verify local execution of the actual routines you save.

**Current scope: heating only. Cooling and Auto are not implemented.** See the
[cooling roadmap](docs/COOLING_ROADMAP.md) for future work.

## Why this driver exists

On the tested Nest (firmware 2.2), successful Matter Thermostat AttributeList
reads omitted both PIHeatingDemand (`0x0008`) and ThermostatRunningState
(`0x0029`), including while the Nest screen showed heating and idle. The normal
Matter interface still reports temperature, setpoint, and mode.

This driver calculates demand from those readings. **It does not reproduce or
read the Nest's internal heating algorithm.** Its status may differ from the
Nest screen, particularly near the setpoint.

Example installation:

```text
Nest Thermostat -> Matter -> SmartThings hub -> routines -> Zooz ZEN17
                                                        -> zone controller
```

The thermostat can be powered independently. This repository does not provide
wiring instructions; identify the correct relay component for your zone.

## How calculation works

| Condition | Calculated state |
|---|---|
| Heat mode and temperature <= setpoint minus 0.5 C (0.9 F) | heating |
| Already heating and temperature remains below setpoint | heating |
| Temperature reaches or exceeds setpoint | idle |
| Already idle inside the hysteresis band | idle |
| Off, Cool, Auto, or any mode other than Heat | idle |
| Missing, invalid, or stale required input | idle |

Calculations use raw Matter values in hundredths of a degree Celsius, regardless
of the display unit. The 0.5 C hysteresis is currently fixed in
[`src/calculated_heating.lua`](src/calculated_heating.lua).

The driver reads temperature, heating setpoint, and mode five seconds after
startup and every 60 seconds. Normal Matter subscriptions also remain active.
An input is stale after five minutes; the periodic check can detect this up to
one further minute later. Repeated reports of an unchanged value renew freshness.
After restart the driver requires fresh reports before publishing heating.

Only Nest vendor `0x6006`, product `0x0001`, endpoint 1 receives this custom
calculation. It requires Edge API >= 15 and RPC >= 9; it was tested on hub
firmware 0.62. Existing temperature, setpoint, and mode commands remain available.
The existing modular profile enables the standard operating-state capability.
No custom capabilities or profile YAML changes are required.

This driver does not enforce minimum relay on/off times or compressor protection.
A hub outage cannot publish an idle event. Account for those limits before
connecting routines to real equipment.

## Install on your hub

Prerequisites: a Matter-paired Nest, a compatible SmartThings hub, SmartThings
CLI authenticated to your account, and a development channel you own. Commands
were checked using CLI 2.1.3. A newer CLI may present different prompts.

Clone this fork and enter `drivers/Personal/nest-matter-thermostat/` for the
installation commands below. Record the Nest's current driver
ID for rollback. Use your own IDs and your hub's LAN IPv4 address:

```sh
export HUB_ID='YOUR_HUB_ID'
export NEST_DEVICE_ID='YOUR_NEST_DEVICE_ID'
export HUB_ADDRESS='YOUR_HUB_LAN_IPV4_ADDRESS'

smartthings devices "$NEST_DEVICE_ID" --json
smartthings edge:drivers:installed --hub "$HUB_ID"
export OFFICIAL_DRIVER_ID='CURRENT_DRIVER_ID_FROM_THE_OUTPUT'
```

Keep the official driver installed. Create a development channel if needed;
provide a name, description, terms URL, and DRIVER type if prompted. The driver
is Apache-2.0 licensed. Reuse an existing enrolled channel if you have one.

```sh
smartthings edge:channels:create
export CHANNEL_ID='YOUR_DEVELOPMENT_CHANNEL_ID'
smartthings edge:channels:enroll "$HUB_ID" --channel "$CHANNEL_ID"
```

Build locally, then upload. This package has a distinct package key,
`nest-matter-thermostat-calculated`, so it does not overwrite the official driver.

```sh
mkdir -p artifacts
smartthings edge:drivers:package . \
  --build-only artifacts/nest-matter-thermostat-calculated.zip
smartthings edge:drivers:package \
  --upload artifacts/nest-matter-thermostat-calculated.zip

export CALCULATED_DRIVER_ID='UPLOADED_DRIVER_ID'
export CALCULATED_DRIVER_VERSION='UPLOADED_VERSION'
smartthings edge:channels:assign "$CALCULATED_DRIVER_ID" "$CALCULATED_DRIVER_VERSION" \
  --channel "$CHANNEL_ID"
smartthings edge:drivers:install "$CALCULATED_DRIVER_ID" \
  --channel "$CHANNEL_ID" --hub "$HUB_ID"
```

Start logs in another terminal with the same variables:

```sh
smartthings edge:drivers:logcat "$CALCULATED_DRIVER_ID" \
  --hub-address "$HUB_ADDRESS" --log-level debug
```

Switch the existing Nest; no deletion, reset, or re-pairing is required:

```sh
smartthings edge:drivers:switch "$NEST_DEVICE_ID" \
  --hub "$HUB_ID" --driver "$CALCULATED_DRIVER_ID"
```

Reopen the Nest in SmartThings if needed. It should expose Thermostat operating
state with heating and idle. Inspect current values with:

```sh
smartthings devices:status "$NEST_DEVICE_ID" --json
```

## Verify before adding relay routines

1. Note your preferred setpoint; keep the Nest in Heat mode.
2. Raise its physical setpoint at least 0.9 F above the room temperature. Check
   SmartThings operating state becomes heating and logs show CALCULATED_HEATING.
3. Lower it below room temperature. Check the operating state becomes idle.
4. Restore your preferred setpoint.

The live test used about 73.4 F room temperature: 77 F produced calculated
heating; 68 F produced calculated idle, confirmed in hub logs and SmartThings
status. Both setpoint reports arrived through Matter. This verifies calculated
state transitions, not correspondence with Nest's proprietary algorithm or
operation of a boiler/relay.

## Use SmartThings routines

Create two routines on the **same relay component**:

- If Nest Thermostat operating state is Heating -> relay On.
- If Nest Thermostat operating state is Idle -> relay Off.

Test with your physical setpoint, check the correct relay responds, and verify
that the saved routines execute locally. Neither routine is created by this
driver. Avoid conflicting temperature-based or scheduled relay automations.
There is no cooling routine in this release.

## Rollback

Switch the Nest back to the official driver you recorded:

```sh
smartthings edge:drivers:switch "$NEST_DEVICE_ID" \
  --hub "$HUB_ID" --driver "$OFFICIAL_DRIVER_ID"
```

Verify normal temperature, setpoint, and mode reporting. Disable or adjust
routines that depend on calculated operating state when rolling back: the
official driver may no longer expose it, and switching drivers does not itself
turn a relay off. Only after rollback, optionally uninstall this driver:

```sh
smartthings edge:drivers:uninstall "$CALCULATED_DRIVER_ID" --hub "$HUB_ID"
```

## Development and tests

Run the development commands below from the **repository root**, not the driver directory.

The Edge package lives under `drivers/Personal/nest-matter-thermostat/` and
contains `config.yml`, `fingerprints.yml`, `profiles/`, and `src/`. Its `src/test/`
directory contains upstream and custom integration tests.
[`UPSTREAM.md`](UPSTREAM.md) records the source revision and modifications.

Install Lua **5.3**, Python 3, and luacheck. On Ubuntu:

```sh
sudo apt-get update
sudo apt-get install lua5.3 lua-check python3
```

On macOS, Homebrew supplies luacheck, but no longer supplies lua@5.3. Build the
hub-compatible runtime separately (requires Xcode command-line tools):

```sh
brew install luacheck
mkdir -p .cache
curl --fail --location https://www.lua.org/ftp/lua-5.3.6.tar.gz \
  --output .cache/lua-5.3.6.tar.gz
tar -xzf .cache/lua-5.3.6.tar.gz -C .cache
make -C .cache/lua-5.3.6 macosx
make -C .cache/lua-5.3.6 install INSTALL_TOP="$PWD/.local/lua53"
export LUA53="$PWD/.local/lua53/bin/lua"
```

Download the tested official SmartThings SDK; it stays untracked:

```sh
mkdir -p .cache lua_libs
curl --fail --location \
  https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/releases/download/apiv21_62/lua_libs-api_v21_62X.tar.gz \
  --output .cache/sdk.tar.gz
printf '%s  %s\n' \
  '6956bb74f8a2e08f6fc513d9239717885f0f9fb03beee8339be8e5b1bcaa2b0d' \
  '.cache/sdk.tar.gz' | shasum -a 256 --check
tar -xzf .cache/sdk.tar.gz -C lua_libs --strip-components=1
```

Run tests and lint:

```sh
# Linux, or any setup with a lua5.3 executable:
python3 tools/run_nest_tests.py
# macOS with the runtime built above:
python3 tools/run_nest_tests.py --lua "$LUA53"

luacheck --config .github/workflows/.luacheckrc drivers/Personal/nest-matter-thermostat/src
```

The runner also accepts `--sdk /path/to/lua_libs`, `--filter REGEX`, and `-v`.
It uses Python's standard library and does not need Python package installation.
CI downloads the pinned SDK, checks its SHA-256, and runs tests and lint.

Custom tests cover hysteresis, duplicate suppression, setpoint and mode changes,
missing/invalid/stale inputs, restart, periodic reads, profile selection,
manufacturer/endpoint isolation, preservation of normal events, and suppression
of native running-state reports for this Nest.

## Troubleshooting

- No operating state: verify the selected driver, supported Nest identifiers,
  hub version, profile update, and fresh Matter reports. Reopen SmartThings.
- Idle when heat is expected: check Heat mode, temperature/setpoint difference,
  hysteresis, and CALCULATED_HEATING freshness logs.
- State differs from Nest screen: expected near thresholds; this is calculated
  demand rather than Nest's native output.
- THERMOSTAT_DIAG reports both demand attributes absent: expected for the tested
  firmware; those messages describe native support, not the calculated state.
- Relay does not follow: inspect the routine condition and relay component;
  relay control is outside this driver. Check local execution separately.

## License

Apache-2.0. Original SmartThings copyright notices are retained; see
[LICENSE](../../../LICENSE) and [UPSTREAM.md](UPSTREAM.md).
