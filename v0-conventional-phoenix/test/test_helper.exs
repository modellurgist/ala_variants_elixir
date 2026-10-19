Mox.defmock(GoodDeal.Payments.MockProvider, for: GoodDeal.Payments.Provider)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(GoodDeal.Repo, :manual)
