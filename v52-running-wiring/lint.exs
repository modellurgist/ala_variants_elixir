# Layer-aware ala_lint for this variant, at every tier.
#   cd ../../ala_lint_elixir && mix run ../ala_variants_elixir/v52-running-wiring/lint.exs
lib = Path.expand("lib", __DIR__)

layers = [
  {:app,
   [
     ~r/GoodDealWeb\.CartLive\./,
     ~r/GoodDealWeb\.PortalLive\./,
     ~r/GoodDealWeb\.ProductLive\./,
     ~r/GoodDealWeb\.PageController$/,
     ~r/GoodDealWeb\.Plugs\./,
     ~r/GoodDealWeb\.CartSession$/,
     ~r/GoodDealWeb\.CheckoutMetadata$/,
     ~r/GoodDealWeb\.Router$/,
     ~r/GoodDealWeb\.Layouts$/,
     ~r/GoodDealWeb\.PageHTML$/,
     ~r/GoodDeal\.Catalog$/
   ], [peer_ok: true]},
  {:feature, [~r/GoodDealWeb\.Stories\./], [peer_ok: false]},
  {:domain,
   [
     ~r/GoodDeal\.Domain\./,
     ~r/GoodDeal\.Actions\./,
     ~r/GoodDeal\.State\./,
     ~r/GoodDeal\.Lines$/,
     ~r/GoodDeal\.Components\./
   ], [peer_ok: true]},
  {:platform,
   [
     ~r/GoodDeal\.Foundation\./,
     ~r/GoodDeal\.Repo$/,
     ~r/GoodDeal\.Mailer$/,
     ~r/GoodDeal\.Money$/,
     ~r/GoodDealWeb\.Paradigms\./,
     ~r/GoodDeal\.Paradigms\./,
     ~r/GoodDealWeb$/,
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

for {tier, opts} <- [normal: [], strict: [strict: true], super_strict: [super_strict: true]] do
  r = AlaLint.analyze(lib, [layers: layers, exclude: exclude] ++ opts)
  IO.puts("#{tier}: #{r.score}/#{r.grade}  by_rule=#{inspect(r.by_rule)}  funcs=#{r.functions}")

  if tier == :super_strict do
    for f <- r.findings,
        do:
          IO.puts(
            "  [#{f.rule}] #{f.file && Path.relative_to(f.file, lib)}:#{f.line} #{f.message}"
          )
  end
end
