# GoodDealWeb.PortalLive.Show, as it ran

```mermaid
flowchart LR
  outside -->|"add"| draft
  outside -->|"expire"| draft
  draft -.->|"contents"| page_draft_contents[page]
  draft -.->|"pending"| page_draft_pending[page]
  draft -.->|"restored"| page_draft_restored[page]
  draft -.->|"stock"| page_draft_stock[page]
```
