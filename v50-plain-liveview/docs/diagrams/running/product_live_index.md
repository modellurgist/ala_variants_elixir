# GoodDealWeb.ProductLive.Index, as it ran

```mermaid
flowchart LR
  outside --> product_form
  product_form -.->|"form"| page_product_form_form[page]
  product_form -.->|"saved"| page_product_form_saved[page]
  product_form -->|"submit"| product_form
```
