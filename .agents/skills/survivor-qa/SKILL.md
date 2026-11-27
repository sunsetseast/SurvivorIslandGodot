---
name: survivor-qa
description: Triage Survivor Island gameplay feedback, reproduce defects, verify proposed fixes and run targeted regressions; use for QA or an explicitly requested bug fix, not feature expansion.
---

# Gameplay QA
- Establish exact build/commit, device, reproduction steps, expected vs actual behavior, and available screenshots/logs. Keep reported bugs, improvement requests and verified fixes distinct.
- Prioritize P0 (progress blocked/data loss/security), P1 (major gameplay failure), P2 (usability/quality), P3 (minor polish). Severity depends on demonstrated impact.
- Reproduce on the relevant production path where possible. Locate existing tests and add a failing regression before fixing when practical. Do not change gameplay unless the user requested implementation.
- Test normal, boundary, alternate and recovery paths; for marooning include timer/early departure/cutoff, collision/boarding, paddling, camera, shore arrival and camp handoff as applicable to approved phase scope. Test concurrent tribes, touch cancellation, save/reload and pause/resume when affected.
- Run targeted tests and proportionate broader checks using the existing toolchain. A mock-only test or headless pass cannot verify visual quality or real device controls.
- Record per issue: ID, priority, status (reported, reproduced, proposed, implemented-unverified, automated-verified, owner-device-verified, deferred), evidence, expected behavior, acceptance checks, regression coverage, build SHA, remaining manual steps. Never label a proposal or code inspection as a verified fix.
