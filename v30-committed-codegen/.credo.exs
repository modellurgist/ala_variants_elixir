# V28 — Credo configuration
#
# Enforces v28's central invariant with one custom check: the pure
# application core (cart aggregate, capabilities, effects, session,
# domain abstractions) never depends on Phoenix or the web layer.
# Everything else uses Credo's defaults.

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/lib/zero_coupled/credo/"]
      },
      plugins: [],
      requires: ["lib/zero_coupled/credo/core_purity.ex"],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: %{
        extra: [
          {ZeroCoupled.Credo.CorePurity, []}
        ]
      }
    }
  ]
}
