---
id: req.auth.001
title: User Authentication
type: requirement
tags: [auth, security, core]
updated: 2025-01-24
language: en
---
The system must support user authentication with email and password.
Passwords must be at least 8 characters and support special characters.
Users must be able to reset their password via email.

connections:
  validated_by:
    - connection_type: validated_by
      target_id: test.auth.001
      weight: 90
  blocked_by:
    - connection_type: blocked_by
      target_id: issue.001
      weight: 100
