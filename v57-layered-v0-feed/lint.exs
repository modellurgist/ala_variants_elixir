# Layer-aware ala_lint for this variant, at every tier.
#   cd ../../ala_lint_elixir && mix run ../ala_variants_elixir/v57-layered-v0-feed/lint.exs
lib = Path.expand("lib", __DIR__)

layers = [
  {:app,
   [
     ~r/GoodDealWeb\.CartLive\./,
     ~r/GoodDealWeb\.CheckoutLive\./,
     ~r/GoodDealWeb\.PortalLive\./,
     ~r/GoodDealWeb\.ProductLive\./,
     ~r/GoodDealWeb\.PageController$/,
     ~r/GoodDealWeb\.Plugs\./,
     ~r/GoodDealWeb\.CartSession$/,
     ~r/GoodDealWeb\.Router$/,
     ~r/GoodDealWeb\.Layouts$/,
     ~r/GoodDealWeb\.PageHTML$/,
     ~r/GoodDealWeb\.ShopComponents$/,
     ~r/GoodDealWeb\.UndoRemoval$/,
     ~r/GoodDealWeb\.LiveProducts$/,
     ~r/GoodDealWeb\.Calibration$/,
     # the `use GoodDealWeb` macros import this app's page components
     ~r/GoodDealWeb$/
   ], [peer_ok: true]},
  {:contexts, [~r/^GoodDeal\.(Catalog|ShoppingCart|Orders|Payments)$/], [peer_ok: false]},
  {:domain, [~r/GoodDeal\.Domain\./], [peer_ok: false]},
  {:platform,
   [
     ~r/^GoodDeal$/,
     ~r/GoodDeal\.Repo$/,
     ~r/GoodDeal\.Mailer$/,
     ~r/GoodDeal\.ChangeFeed$/,
     # configuration and session structs, passed down whole
     ~r/^GoodDeal\.(Channel|Shop)$/,
     ~r/^GoodDeal\.Catalog\.Product$/,
     ~r/^GoodDeal\.ShoppingCart\.(Address|Cart|CartItem|WishlistItem)$/,
     ~r/^GoodDeal\.Orders\.(LineItem|Order|PurchaseOrder)$/,
     ~r/^GoodDeal\.Payments\.(Provider|InProcessProvider)$/,
     ~r/GoodDealWeb\.CoreComponents$/
   ], [peer_ok: true]}
]

exclude = [
  ~r/telemetry\.ex$/,
  ~r/gettext\.ex$/,
  ~r/endpoint\.ex$/,
  ~r/error_(html|json)\.ex$/,
  ~r/application\.ex$/,
  ~r{/components/core_components\.ex$},
  ~r{/components/layouts}
]

# Form 1 adopts dependency direction, calibration at the top and named rules, not ports,
# wiring or composition-only pages, so the checks about those are off (DESIGN.md).
checks = %{
  r9: :off,
  r10: :off,
  r10_aggregate: :off,
  r11: :off,
  r11_share: :off,
  ports: :off,
  ports_unwired: :off,
  ports_computed: :off,
  wiring_closure: :off,
  hops: :off,
  vocabulary: :off,
  subcomponent: :off
}

for {tier, opts} <- [normal: [], strict: [strict: true], super_strict: [super_strict: true]] do
  r = AlaLint.analyze(lib, [layers: layers, exclude: exclude, checks: checks] ++ opts)
  IO.puts("#{tier}: #{r.score}/#{r.grade}  by_rule=#{inspect(r.by_rule)}  funcs=#{r.functions}")

  if tier == :super_strict do
    for f <- r.findings,
        do:
          IO.puts(
            "  [#{f.rule}] #{f.file && Path.relative_to(f.file, lib)}:#{f.line} #{f.message}"
          )
  end
end
