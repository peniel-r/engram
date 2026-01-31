---
id: feat.yaml-configuration-file-support
title: YAML Configuration file support
type: feature
tags: ["feature"]

context:
  status: active
  priority: 3

updated: "2026-01-31T18:55:51Z"
language: en
---

# YAML Configuration file support

## Overview

Configuration file support using YAML format.

## Business Value

13

## Requirements

Using the already implemented YAML parser add .yaml configuration file support

- The file should be called "config.yaml"
- It should be located in the ~/.config/engram/ directory for both Windows and Unix-like systems
- If the file doesn't exist, it should be created with the default configurations
- Add a "engram open-config" command to open the yaml file using the default text editor
- Suggested configurations:
  - editor: "hx" # notepad, code, vim, emacs, etc
  - default-artifact-type: "feature"
- The configuration file is created with the default configurations
- The configuration file is loaded when the application starts
- The configuration file is loaded when the application is run from the command line
- If the configuration file is not found, the application should use the default configurations
- If the configuration file is found but cannot be parsed, the application should use the default configurations and log an error
- If the configuration file is found but contains invalid configurations, the application should use the default configurations and log an error

## Success Metrics

- Configuration file is created with the default configurations.
- Configuration file is correctly parsed and validated at startup.
- Max time for config file parsing and validation is 100ms.
