defmodule ZeroCoupledWeb.StoreConfig do
  @moduledoc "The store's calibration and words shared by its pages: shipping rates, the low-stock threshold, the undo window, and the labels both pages show."
  def rates,
    do: %{
      standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
      express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
      overnight: %{label: "Overnight", cost: 2499, free_above: nil}
    }

  def low_stock_at, do: 5
  def currency, do: "usd"
  def undo_window_ms, do: 5_000

  def summary_texts,
    do: %{
      items: "Items",
      subtotal: "Subtotal",
      shipping: "Shipping",
      free: "Free",
      total: "Total"
    }

  def stock_texts, do: %{low_stock: "Low stock", out_of_stock: "Out of stock"}
  def remove_text, do: "Remove"

  @doc "The product form: its fields, as `{field, input type, label}`, and its words."
  def product_form,
    do: %{
      fields: [
        {:amount, "number", "Amount"},
        {:description, "text", "Description"},
        {:name, "text", "Name"},
        {:stock, "number", "Stock"},
        {:thumbnail, "text", "Thumbnail"}
      ],
      subtitle: "Use this form to manage product records in your database.",
      submit: "Save Product",
      saving: "Saving..."
    }
end
