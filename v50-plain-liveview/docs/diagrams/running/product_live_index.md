# GoodDealWeb.ProductLive.Index, as it ran

```mermaid
flowchart LR
  outside --> feed
  outside --> product_form
  feed -.->|"product"| page_feed_product[page]
  feed -.->|"stock"| page_feed_stock[page]
  product_form -.->|"form"| page_product_form_form[page]
  product_form -.->|"saved"| page_product_form_saved[page]
  product_form -->|"submit"| product_form
```
