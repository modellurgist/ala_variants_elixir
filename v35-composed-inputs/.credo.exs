# V32 — Credo configuration
#
# Three custom checks now govern the whole coupling surface:
#
#   * CorePurity       — the pure core never depends on Phoenix/the web layer
#                        (v28's invariant, unchanged).
#   * ComponentPurity  — the presentation layer depends only on paradigm-typed
#                        ports: no domain refs, no deep domain-shape reads, no
#                        literal event/hook/stream-id strings in markup.
#   * ContractPurity   — cross-boundary string/atom contracts are single-sourced
#                        in `ZeroCoupled.Web.Contracts` (or typed facts), never
#                        restated at effect call sites or as tagged-tuple
#                        handle_info patterns. App-wide.
#
# `mix credo --only Purity` runs exactly these three; the `test` alias runs it,
# so a coupling regression fails the build like a codegen drift.

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/lib/zero_coupled/credo/"]
      },
      plugins: [],
      requires: [
        "lib/zero_coupled/credo/core_purity.ex",
        "lib/zero_coupled/credo/component_purity_rules.ex",
        "lib/zero_coupled/credo/component_purity.ex",
        "lib/zero_coupled/credo/contract_purity.ex"
      ],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: %{
        extra: [
          {ZeroCoupled.Credo.CorePurity, []},
          {ZeroCoupled.Credo.ComponentPurity, []},
          {ZeroCoupled.Credo.ContractPurity, []}
        ]
      }
    }
  ]
}
