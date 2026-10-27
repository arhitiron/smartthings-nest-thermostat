# Upstream provenance

This driver derives from the Apache-2.0 licensed SmartThings Matter Thermostat
Edge driver:

- Repository: https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers
- Source: `drivers/SmartThings/matter-thermostat/`
- Base commit: `3a48d3d84f322810bafa030432c53ce91b5488a7`

Original copyright and license notices are retained. The Apache License is
included in LICENSE. Existing embedded clusters, profiles, fingerprints, and
upstream tests remain in the package for compatibility; their presence does not
mean this project independently verified every upstream device or feature.

Local modifications add read-only attribute diagnostics, calculated heating
state for the Nest Thermostat (2020), runtime optional-capability selection,
native-state suppression, periodic input reads, freshness handling, and tests.

Standalone additions provide documentation, a test runner, and CI. SmartThings
Lua SDK files are downloaded separately and are not redistributed in this repo.

This project is not an official Google, Samsung, SmartThings, or Zooz product.
