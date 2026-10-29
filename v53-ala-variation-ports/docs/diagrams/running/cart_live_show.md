# GoodDealWeb.CartLive.Show, as it ran

```mermaid
flowchart LR
  outside -->|"add_product"| draft
  outside -->|"expire"| draft
  outside -->|"receive"| draft
  outside -->|"request_checkout"| draft
  draft -.->|"checkout_requested"| page_draft_checkout_requested[page]
  draft -.->|"contents"| page_draft_contents[page]
  draft -.->|"line"| page_draft_line[page]
  draft -.->|"pending"| page_draft_pending[page]
  draft -.->|"restored"| page_draft_restored[page]
  draft -.->|"saved"| page_draft_saved[page]
  draft -.->|"stock"| page_draft_stock[page]
```
