ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ZeroCoupled.Repo, :manual)

Mox.defmock(ZeroCoupled.MockPaymentGateway, for: ZeroCoupled.Foundation.PaymentGateway)
Application.put_env(:zero_coupled, :payment_gateway, ZeroCoupled.MockPaymentGateway)
