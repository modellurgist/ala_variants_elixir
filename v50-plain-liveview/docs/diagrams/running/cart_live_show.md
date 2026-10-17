# GoodDealWeb.CartLive.Show, as it ran

```mermaid
flowchart LR
  outside --> cart
  outside --> checkout
  outside --> saved
  outside --> ui
  outside --> undo
  outside --> wishlist
  cart -.->|"changed"| page_cart_changed[page]
  cart -->|"checkout_requested"| checkout
  cart -->|"checkout_started"| checkout
  cart -->|"line"| wishlist
  cart -.->|"promo_applied"| page_cart_promo_applied[page]
  cart -.->|"promo_rejected"| page_cart_promo_rejected[page]
  cart -->|"removed"| undo
  cart -.->|"rows"| page_cart_rows[page]
  cart -->|"saved"| saved
  cart -.->|"summary"| page_cart_summary[page]
  checkout -.->|"address"| page_checkout_address[page]
  checkout -.->|"blocked"| page_checkout_blocked[page]
  checkout -.->|"done"| page_checkout_done[page]
  checkout -.->|"form"| page_checkout_form[page]
  checkout -.->|"ready_to_pay"| page_checkout_ready_to_pay[page]
  checkout -.->|"step"| page_checkout_step[page]
  saved -.->|"count"| page_saved_count[page]
  saved -->|"moved"| cart
  saved -.->|"rows"| page_saved_rows[page]
  ui -.->|"tab"| page_ui_tab[page]
  undo -.->|"captured"| page_undo_captured[page]
  undo -->|"expired"| cart
  undo -->|"restored"| cart
  wishlist -.->|"added"| page_wishlist_added[page]
  wishlist -.->|"count"| page_wishlist_count[page]
  wishlist -.->|"dropped"| page_wishlist_dropped[page]
  wishlist -.->|"ids"| page_wishlist_ids[page]
  wishlist -.->|"rows"| page_wishlist_rows[page]
  wishlist -->|"taken"| cart
```
