# Survivor Island — repository instructions

## Project constraints
- Godot 4.7.2, typed GDScript, GL Compatibility. Confirm pinned toolchain in CI before changing it. Primary target: iPhone 17 Pro Max, Safari, landscape, simultaneous two-thumb movement/camera input.
- Single-player first; preserve existing account, save and networking boundaries. No new paid services, dependencies requiring payment, or engine migration without owner approval.
- Public repository: never commit real-contestant likeness assets, private catalogs, credentials, private preview URLs, or personal data. Use technical fixtures and the existing export allowlist; do not weaken private staging guards.
- Preserve both steering modes, existing saves, deterministic simulation, and the separation of presentation from authoritative season state. Follow the approved phase design; do not silently add gameplay scope.
- Work on the requested branch/PR. Do not merge, deploy, alter production configuration, or publish private builds without explicit authorization. Never overwrite unrelated work.

## Efficient workflow
- Resolve the requested phase and current head; consult only relevant documentation and files. `docs/TECHNICAL_DESIGN.md`, the latest relevant phase documentation and the actual code/tests are starting points; older docs may be stale.
- Use a focused skill when appropriate: `survivor-implement`, `survivor-qa`, `survivor-review` in `.agents/skills/`. Explicit paths work even where a client cannot discover skills automatically.
- Prefer existing systems and tests over new frameworks. Add focused regression coverage for changed behavior; run appropriate existing checks. See `docs/DEVELOPMENT_WORKFLOW.md` for commands and reporting.
- Distinguish tested results from assumptions; record exact commands, commit, outcomes and blockers. Headless or desktop evidence is not owner iPhone acceptance. Do not claim a fix, deployment or playable preview without evidence.
- For PR reviews, flag concrete changed-code defects and regressions, especially privacy/security, save integrity, state transitions, touch input and mobile compatibility. Cite file/line and user impact; avoid speculative or cosmetic noise. Do not edit in a review-only task.
