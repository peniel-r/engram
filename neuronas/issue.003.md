---
id: issue.003
title: Connection Error
type: issue
tags: [bug, p3]
updated: 2025-01-24
language: en
---
Database connection fails during user login transactions.
Connection pool exhaustion causes intermittent errors.

connections:
  blocks:
    - connection_type: blocks
      target_id: req.perf.001
      weight: 80
  relates_to:
    - connection_type: relates_to
      target_id: issue.001
      weight: 60
