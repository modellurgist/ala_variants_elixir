# GoodDealWeb.PortalLive.Show, as it ran

```mermaid
flowchart LR
  outside --> catalog
  outside --> feed
  outside --> flow
  outside --> order
  outside --> undo
  catalog -->|"requested"| order
  catalog -.->|"rows"| page_catalog_rows[page]
  feed -->|"stock"| catalog
  feed -->|"stock"| order
  flow -->|"approved"| flow
  flow -.->|"blocked"| page_flow_blocked[page]
  flow -.->|"form"| page_flow_form[page]
  flow -.->|"reference"| page_flow_reference[page]
  flow -.->|"step"| page_flow_step[page]
  order -.->|"changed"| page_order_changed[page]
  order -->|"removed"| undo
  order -->|"review"| flow
  order -.->|"rows"| page_order_rows[page]
  order -.->|"summary"| page_order_summary[page]
  undo -.->|"captured"| page_undo_captured[page]
  undo -->|"expired"| order
  undo -->|"restored"| order
```
