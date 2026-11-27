---
name: survivor-implement
description: Implement an approved Survivor Island phase or targeted gameplay change; use for coding tasks with a defined scope, not design-only planning or read-only PR review.
---

# Phase implementation
1. Resolve target branch/PR, head SHA, approved requirements and relevant tests. If the user requests an amendment, keep the existing PR. Do not assume main contains unmerged work.
2. Identify the smallest coherent changes and acceptance criteria. Use existing simulation, controller, UI and persistence boundaries. Keep unrelated assets, refactors and future phases out of scope.
3. Implement the requested behavior, including failure and recovery paths. Prefer reusable existing components; avoid temporary hacks presented as finished features.
4. Add or update focused regression tests, then run relevant existing checks per `docs/DEVELOPMENT_WORKFLOW.md`. A new test must exercise the production path, not merely duplicate its logic. Avoid weakening assertions.
5. Update only affected design/validation docs. Report commit, changed behavior, acceptance criteria, commands/results, limitations, and owner device-test steps. Provide a preview only if explicitly authorized and actually verified.
6. Follow repository branch/merge/publication rules. If blocked by missing tools, assets or authorization, report the blocker and safe partial results rather than inventing success.
