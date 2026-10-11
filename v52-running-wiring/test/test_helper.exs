ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(GoodDeal.Repo, :manual)

Mox.defmock(GoodDeal.MockPaymentGateway, for: GoodDeal.Foundation.PaymentGateway)
Application.put_env(:good_deal, :payment_gateway, GoodDeal.MockPaymentGateway)

# The wiring as it ran: every hop the pages route during the suite is recorded, the diagrams are
# drawn from those hops, and a declared output no test ever routed fails the run.
alias GoodDealWeb.Paradigms.Trace
Trace.enable()

ExUnit.after_suite(fn _ ->
  pages = [GoodDealWeb.CartLive.Show, GoodDealWeb.PortalLive.Show]
  File.mkdir_p!("docs/diagrams/running")

  unrouted =
    for page <- pages do
      name = page |> Module.split() |> Enum.drop(1) |> Enum.map_join("_", &Macro.underscore/1)

      File.write!(
        "docs/diagrams/running/#{name}.md",
        "# #{inspect(page)}, as it ran\n\n```mermaid\n#{Trace.mermaid(page)}```\n"
      )

      {page, Trace.unrouted(page)}
    end
    |> Enum.reject(fn {_, ports} -> ports == [] end)

  if unrouted == [] do
    IO.puts(
      "\nrunning wiring: every declared output routed during this run; diagrams in docs/diagrams/running/"
    )
  else
    IO.puts("\nrunning wiring: declared outputs no test routed: #{inspect(unrouted)}")
    exit({:shutdown, 1})
  end
end)
