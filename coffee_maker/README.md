# coffee_maker

The ALA coffee-maker domain, extracted from the `ala_lab` study (originally
`AlaLab.CoffeeMachineV3.*`) and renamed to `CoffeeMaker.*`. It is the worked
example behind the coffee-maker LiveView blog post.

The domain is **dependency-free** and compiles/tests on its own:

```bash
mix deps.get   # none, but harmless
mix test       # 35 tests
```

## Layout

- `lib/coffee_maker.ex` — `CoffeeMaker`, the composition (the ALA application layer).
- `lib/coffee_maker/server.ex` — a GenServer driving the maker from hardware readings.
- `lib/coffee_maker/domain_abstractions/` — `Boiler`, `WarmerPlate`, `UserInterface`.
- `lib/coffee_maker/foundation/` — `HardwareApi`, `SimulatedHardware`, and the
  `HardwareCommand` / `SensorReading` value structs.
- `lib/coffee_maker/compose/` — the `Step` protocol and `Chain`, the vendored ALA
  composition primitives (the Elixir analogue of ALA's programming-paradigm port).
- `reference/coffee_live.ex` — the Phoenix LiveView that drives the maker. It is
  **not compiled here** (it needs a Phoenix host module `CoffeeMakerWeb`); it is
  kept as a reference for how the domain wires into a LiveView.

## License

Part of `ala_variants_elixir`, licensed under the [MIT License](../LICENSE).
