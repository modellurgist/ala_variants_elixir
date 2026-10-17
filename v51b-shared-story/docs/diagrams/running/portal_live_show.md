# GoodDealWeb.PortalLive.Show, as it ran

```mermaid
flowchart LR
  outside -->|"stock"| catalog
  outside -->|"stock"| edit_lines
  outside -->|"goto"| submit
  outside -->|"expire"| undo
  catalog -->|"requested → add"| edit_lines
  edit_lines -->|"contents → contents"| price
  edit_lines -->|"removed → capture"| undo
  price -->|"review → review"| submit
  price -.->|"summary"| page_price_summary[page]
  submit -.->|"form"| page_submit_form[page]
  submit -.->|"po"| page_submit_po[page]
  submit -.->|"reference"| page_submit_reference[page]
  submit -.->|"step"| page_submit_step[page]
  undo -->|"expired → confirm_removal"| edit_lines
  undo -.->|"pending"| page_undo_pending[page]
  undo -->|"restored → receive"| edit_lines
```
