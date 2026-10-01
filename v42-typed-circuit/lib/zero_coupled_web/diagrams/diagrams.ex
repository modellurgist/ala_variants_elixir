defmodule ZeroCoupledWeb.Diagrams do
  @moduledoc "Each page's diagram, drawn with sample configuration, and where its drawing lives."
  alias ZeroCoupled.Paradigms.Drawing

  def drawings do
    [
      {"docs/diagrams/cart.mmd",
       Drawing.mermaid(
         ZeroCoupledWeb.CartDiagram.circuit(%{
           cart_id: 0,
           charge: &ZeroCoupledWeb.CartPage.charge/1
         })
       )},
      {"docs/diagrams/portal.mmd",
       Drawing.mermaid(ZeroCoupledWeb.PortalDiagram.circuit(%{cart_id: 0}))}
    ]
  end
end
