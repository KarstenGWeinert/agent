---
name: forgejo
description: High-level overview and index for the local Forgejo instance, CI pipeline, and infrastructure.
---

# Forgejo Environment Guide

To maintain a clear separation of concerns and avoid mixing development workflows with infrastructure details, this documentation is split into three focused guides. 

Please select the document that matches your current task:

## 1. [Contributing Guide](CONTRIBUTING.md)
**Target Audience:** Developers writing code, submitting PRs, or interacting with the repository.
* Secure Git cloning instructions (avoiding token leakage)
* Git commit and push conventions
* Using the local `fj` CLI for managing repositories, PRs, and issues

## 2. [CI/CD Pipeline](PIPELINE.md)
**Target Audience:** CI authors maintaining or troubleshooting the Forgejo Actions workflow.
* Architecture and run conditions of the multi-job pipeline
* Best practices for building and testing with immutable Git SHA tags
* Container registry authentication and package pushing
* Network-isolated deployment health checks

## 3. [Infrastructure & Platform](INFRASTRUCTURE.md)
**Target Audience:** Platform engineers managing the Forgejo server, runners, or API integrations.
* Host configuration and custom Docker bridge networks (`dev-network`)
* Actions runner registration and management
* Robust, fail-safe API scripting patterns for fetching logs and registry tags

