# Credo for this variant: the layer boundaries of `lint.exs`'s layer map, checked on every
# alias/import/use/require. ala_lint checks calls too; this catches an upward reference at review.

app = [
  "GoodDealWeb.CartLive",
  "GoodDealWeb.PortalLive",
  "GoodDealWeb.ProductLive",
  "GoodDealWeb.PageController",
  "GoodDealWeb.Plugs",
  "GoodDealWeb.CartSession",
  "GoodDealWeb.CheckoutMetadata",
  "GoodDealWeb.Router",
  "GoodDeal.Catalog"
]

features = ["GoodDealWeb.Stories"]

domain = [
  "GoodDeal.Domain",
  "GoodDeal.Actions",
  "GoodDeal.State",
  "GoodDeal.Lines",
  "GoodDeal.Components"
]

layer = fn name, paths, forbidden ->
  for path <- paths, do: %{name: name, path: path, forbidden_prefixes: forbidden}
end

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/lib/good_deal/credo/"]
      },
      plugins: [],
      requires: ["lib/good_deal/credo/ala_layer_boundary.ex"],
      strict: true,
      color: true,
      checks: %{
        enabled: [
          {Credo.Check.Custom.AlaLayerBoundary,
           [
             layers:
               layer.("Features", ["lib/good_deal_web/stories/"], app) ++
                 layer.(
                   "Domain abstractions",
                   [
                     "lib/good_deal/domain/",
                     "lib/good_deal/actions/",
                     "lib/good_deal/state/",
                     "lib/good_deal/components/",
                     "lib/good_deal/lines.ex"
                   ],
                   app ++ features
                 ) ++
                 layer.(
                   "Platform",
                   [
                     "lib/good_deal/foundation/",
                     "lib/good_deal/paradigms/",
                     "lib/good_deal_web/paradigms/"
                   ],
                   app ++ features ++ domain
                 )
           ]}
        ]
      }
    }
  ]
}
