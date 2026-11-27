# Development efficiency and verification

This guide supports the root AGENTS.md and three repo-local Codex skills. It is intentionally independent of any active gameplay PR.

## Start a task
Use the current target branch/PR, not an assumed historical head. On a client supporting skill mentions, use $survivor-implement, $survivor-qa or $survivor-review; otherwise explicitly ask the agent to read the corresponding .agents/skills/<name>/SKILL.md. No separate package or paid service is required for these files. Skill discovery depends on the client.

Minimal phase prompt:
- Target: branch or PR, approved phase and scope.
- Requirements: new behavior and non-goals.
- Acceptance: observable outcomes and important edge cases.
- Evidence: relevant screenshots, QA IDs or design-doc paths.
- Delivery: requested PR/amendment and any explicitly authorized preview.

Example: "Use $survivor-implement. Amend PR #17 only. Implement the approved marooning changes listed below; preserve existing behavior outside scope. Run targeted and relevant regression checks, report exact head SHA and remaining iPhone tests." Append the actual requirements, not just the example.

## Reuse existing verification
Read the target branch's scripts first; commands and test inventory evolve. On the baseline main at 75090ff8, the README and CI identify:
- `bash ci/install-godot-web.sh`: pinned Godot and matching template.
- `bash ci/build-web.sh`: Phase 0 smoke test and web export.
- `bash ci/build-tonsai.sh`: prepare public-safe stage, import, bake navigation, execute staged tests and export. This is more expensive than a focused test; use once for relevant integrated changes rather than repeatedly rebuilding.
- For a prepared stage, the current build script invokes tests such as `godot --headless --path build/tonsai-project --fixed-fps 60 --script res://tests/marooning_test.gd` with the pinned binary. Ensure the stage contains the exact target revision and required assets; a stale stage invalidates evidence. Inspect the current script for flags and all test names.
- Existing Actions workflow `.github/workflows/ios-safari-web-export.yml` runs the Phase 0 build on PRs, while fuller Tonsai/character lab builds and Pages deployment are main-only on this baseline. A green PR smoke check alone does not prove Tonsai regressions passed. Other workflows and newer branches may differ.

Active marooning PR #17 already adds many focused tests, including concurrent physics, ship access, moving boarding, supply deposits, strokes, shallow exits and race/session behavior. Reuse them once available on the target branch. This foundation does not duplicate or claim to run them. After that PR is resolved, audit which relevant checks run before merge and consider a public-safe, non-deploying targeted PR job, with path filters and cancellation to avoid redundant builds. Do not enable paid AI review or change workflow permissions automatically.

## Test evidence and owner acceptance
Record test command, commit SHA, environment, status (pass/fail/not run), and reason for any missing evidence. Keep automated logic tests, desktop browser checks and actual iPhone Safari acceptance separate. Check touch movement/orbit, landscape/resume, camera readability, performance and any phase-specific acceptance criteria on device. Only an owner-confirmed test is owner-device-verified.

Suggested PR handoff:
- Scope and exclusions
- Acceptance criteria and status
- Regression tests added/reused and actual results
- Risks, blockers and remaining manual checks
- Exact head SHA; verified authorized preview if applicable
- Recommendation (not a merge action)

## Review and cost discipline
Use review-only skill after implementation if meaningful risk warrants it. Repository-specific review guidance is in AGENTS.md; enabling automatic Codex reviews is an owner-controlled account/repository setting, not part of this PR. Avoid duplicate reviews for trivial docs-only changes. Do not use a full repository audit when a targeted diff is enough. Start with these three skills and add more only after repeated need is demonstrated.
