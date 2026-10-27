# Nest Thermostat calculated operating state

This is a GitHub-linked fork of [SmartThings Edge Drivers](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers).
Our custom Nest Thermostat (2020) driver publishes calculated **heating / idle**
for local SmartThings routines controlling a separate relay. It runs on the hub
and does not directly command the relay. **Cooling is planned, not implemented.**

- [Driver setup, use, tests, and rollback](drivers/Personal/nest-matter-thermostat/README.md)
- [Future cooling and Auto roadmap](drivers/Personal/nest-matter-thermostat/docs/COOLING_ROADMAP.md)
- [Upstream provenance](drivers/Personal/nest-matter-thermostat/UPSTREAM.md)
- [Original standalone repository and history](https://github.com/arhitiron/smartthings-nest-thermostat-standalone)

The official drivers remain intact under `drivers/SmartThings/`; our changes are
isolated under `drivers/Personal/nest-matter-thermostat/` with a separate package key.

## Syncing upstream

From a clone of this fork, add upstream once, then merge updates:

```sh
git remote add upstream https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers.git
git fetch upstream
git switch main
git merge upstream/main
```

Review and test changes before pushing or deploying. A local `upstream` remote
is configured in the migration checkout. Re-run the Nest tests and review
upstream Matter Thermostat changes for relevant fixes; updates in the official
driver directory do not automatically modify our separate copied driver.

---

# SmartThingsEdgeDrivers

## What is SmartThings Edge?

SmartThings Edge is our new architecture for Hub Connected devices that uses Device Drivers to execute commands locally on SmartThings Hubs. Edge Drivers are [Lua©-based](https://www.lua.org/) and can be used for Hub Connected devices, including Zigbee, Z-Wave, and LAN protocols. Read more about SmartThings Edge in our [public announcement](https://developer.samsung.com/smartthings/blog/en-us/2021/08/19/new-smartthings-edge-for-devices-and-automations?mc_cid=aac4089a1b&mc_eid=c15e37816a).

## Documentation and Tutorials

Visit the SmartThings Edge Device Driver documentation on our [developer documentation portal](https://developer.smartthings.com/docs/devices/hub-connected/get-started) to get started.

Be sure to check out the SmartThings Community for [tutorials](https://community.smartthings.com/c/developer-programs/tutorials/103), code samples, and more.

## Code of Conduct

The code of conduct for SmartThingsEdgeDrivers can be found in
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## How to Contribute

Pull requests to this repo are intended to be from OEMs submitting pull requests for devices seeking Works With SmartThings (WWST) Certification, for maintaining existing certification, and for bug fixes to existing drivers. For more info on WWST certification and the submission process, visit our [certification documentation](https://developer.smartthings.com/docs/devices/hub-connected/certify-your-device).

By submitting a pull request, you represent that you have the right to
license your contribution to SmartThings and agree by submitting your patch that
your contributions are licensed under the [Apache 2.0 license](LICENSE). Before
submitting your pull request, please make sure you have tested your changes and that
they follow the project guidelines for [contributing code](https://developer.smartthings.com/docs/devices/hub-connected/code-formatting-criteria).

Before contributions can be merged, all contributors must agree to the [SmartThings
Individual Contributor License
Agreement](https://cla-assistant.io/SmartThingsCommunity/SmartThingsEdgeDrivers).

## License

SmartThingsEdgeDrivers is released under the [Apache 2.0 License](LICENSE).
