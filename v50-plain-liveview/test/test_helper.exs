ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(GoodDeal.Repo, :manual)

Mox.defmock(GoodDeal.MockPaymentGateway, for: GoodDeal.Foundation.PaymentGateway)
Application.put_env(:good_deal, :payment_gateway, GoodDeal.MockPaymentGateway)
