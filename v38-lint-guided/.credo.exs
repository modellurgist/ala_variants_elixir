# V27 Explicitly-Wired Features — Credo configuration
#
# Copy this file to good_deal/.credo.exs when running the V27 variant,
# or have switch.sh copy it automatically.
#
# This configuration enforces:
# 1. Vertical ALA layer boundaries (domain, features, foundation)
# 2. Cross-feature independence (no peer feature references)
# 3. Capsule role discipline (Domain: output, no react; UI: react, no output)
# 4. Typed outcome constructors over raw tuples
# 5. Thin LiveView shell (no domain abstractions in LiveView)
# 6. PubSub wiring discipline (no deprecated Broadcast.notify, no direct deliver)

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/lib/good_deal/credo/"]
      },
      plugins: [],
      requires: [
        "lib/good_deal/credo/ala_layer_boundary.ex",
        "lib/good_deal/credo/v27_cross_feature_coupling.ex",
        "lib/good_deal/credo/v27_capsule_discipline.ex",
        "lib/good_deal/credo/v27_outcome_constructor.ex",
        "lib/good_deal/credo/v27_liveview_thin_shell.ex",
        "lib/good_deal/credo/v27_no_broadcast_notify.ex"
      ],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          # ── 1. Vertical ALA layer boundaries ──────────────────────────
          #
          # Domain abstractions: pure logic, no persistence, no Phoenix.
          # Feature capsules: call domain abstractions downward, never
          #   infrastructure, framework, or the wiring table directly.
          # Foundation: no upward deps into Domain, Features, or Web.
          #
          {Credo.Check.Custom.AlaLayerBoundary, [
            layers: [
              %{
                name: "Domain abstractions",
                path: "lib/good_deal/domain/",
                forbidden_prefixes: [
                  "GoodDeal.Foundation",
                  "GoodDeal.Features",
                  "GoodDeal.Actions",
                  "GoodDeal.Wiring",
                  "GoodDeal.Dispatcher",
                  "GoodDealWeb",
                  "Phoenix",
                  "Ecto"
                ]
              },
              %{
                name: "Feature capsules",
                path: "lib/good_deal/features/",
                forbidden_prefixes: [
                  "GoodDeal.Foundation",
                  "GoodDeal.Wiring",
                  "GoodDeal.Dispatcher",
                  "GoodDealWeb",
                  "Phoenix",
                  "Ecto"
                ]
              },
              %{
                name: "Foundation",
                path: "lib/good_deal/foundation/",
                forbidden_prefixes: [
                  "GoodDeal.Domain",
                  "GoodDeal.Features",
                  "GoodDeal.Actions",
                  "GoodDeal.Wiring",
                  "GoodDeal.Dispatcher"
                ]
              }
            ]
          ]},

          # ── 2. Cross-feature independence ──────────────────────────────
          #
          # Feature capsules must not alias/import/use other feature modules.
          # All cross-feature communication flows through the wiring table.
          #
          {Credo.Check.Custom.V27CrossFeatureCoupling, [
            features_path: "lib/good_deal/features/"
          ]},

          # ── 3. Capsule role discipline ─────────────────────────────────
          #
          # Domain capsules: emit output/2, MUST NOT define react/3.
          # UI capsules: define react/3, MUST NOT call output/2.
          #
          {Credo.Check.Custom.V27CapsuleDiscipline, [
            features_path: "lib/good_deal/features/"
          ]},

          # ── 4. Typed outcome constructors ──────────────────────────────
          #
          # Capsules should use flash(:error, msg) not {:flash, :error, msg}.
          #
          {Credo.Check.Custom.V27OutcomeConstructor, [
            capsule_paths: ["lib/good_deal/features/"],
            outcome_tags: [
              :flash, :redirect, :stream_insert, :stream_delete,
              :stream_reset, :push_event, :persist_quantity,
              :persist_remove, :start_checkout, :output,
              :start_undo_timer
            ]
          ]},

          # ── 5. Thin LiveView shell ─────────────────────────────────────
          #
          # LiveView dispatches events to capsules and applies outcomes.
          # It must not call domain abstraction modules directly.
          #
          {Credo.Check.Custom.V27LiveViewThinShell, [
            liveview_path: "lib/good_deal_web/live/",
            forbidden_in_liveview: [
              "GoodDeal.Domain."
            ],
            # Presentation-oriented domain abstractions used in templates:
            # StockStatus (stock badges), ShippingInfo (method labels),
            # CalculateShipping (format shipping cost in helpers).
            # Kept here rather than in capsules because they serve the
            # LiveView's rendering responsibility.
            allowed_in_liveview: [
              "GoodDeal.Domain.StockStatus",
              "GoodDeal.Domain.ShippingInfo",
              "GoodDeal.Domain.CalculateShipping"
            ]
          ]},

          # ── 6. PubSub wiring discipline ────────────────────────────────
          #
          # No Broadcast.notify (deprecated V26 API).
          # No direct Broadcast.deliver outside GoodDeal.Wiring.
          #
          {Credo.Check.Custom.V27NoBroadcastNotify, [
            wiring_module_path: "lib/good_deal/wiring.ex",
            broadcast_module_path: "lib/good_deal/foundation/broadcast.ex"
          ]}
        ]
      }
    }
  ]
}
