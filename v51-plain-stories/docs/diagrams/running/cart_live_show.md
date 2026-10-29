# GoodDealWeb.CartLive.Show, as it ran

```mermaid
flowchart LR
  outside -->|"failed"| check_out
  outside -->|"goto"| check_out
  outside -->|"succeeded"| check_out
  outside -->|"expire"| undo
  check_out -.->|"address"| page_check_out_address[page]
  check_out -.->|"form"| page_check_out_form[page]
  check_out -->|"pay_requested → request_checkout"| edit_cart
  check_out -.->|"step"| page_check_out_step[page]
  edit_cart -->|"checkout_requested → pay"| check_out
  edit_cart -->|"checkout_started → start"| check_out
  edit_cart -->|"line → toggle"| wishlist
  edit_cart -.->|"promo_error"| page_edit_cart_promo_error[page]
  edit_cart -->|"removed → capture"| undo
  edit_cart -->|"saved → stash"| saved
  edit_cart -.->|"summary"| page_edit_cart_summary[page]
  feed -->|"stock → stock"| edit_cart
  saved -.->|"count"| page_saved_count[page]
  saved -->|"moved → receive"| edit_cart
  ui -.->|"tab"| page_ui_tab[page]
  undo -->|"expired → confirm_removal"| edit_cart
  undo -.->|"pending"| page_undo_pending[page]
  undo -->|"restored → receive"| edit_cart
  wishlist -.->|"count"| page_wishlist_count[page]
  wishlist -.->|"ids"| page_wishlist_ids[page]
  wishlist -->|"taken → add_product"| edit_cart
```
