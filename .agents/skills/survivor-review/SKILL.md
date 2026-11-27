---
name: survivor-review
description: Independently review a Survivor Island pull request or diff for requirements coverage, defects, regressions and merge readiness; read-only unless separately authorized to implement fixes.
---

# Independent PR review
1. Resolve PR base/head and compare the actual diff with approved requirements and relevant prior behavior. Read only needed code, docs and tests; do not trust PR claims without evidence.
2. Inspect correctness and edge cases first: state ownership and transitions, save compatibility, privacy/export boundaries, input/camera handling, resource lifetime and mobile performance when relevant.
3. Assess whether tests actually cover changed production behavior, boundary cases and failure recovery. Run targeted checks if available; distinguish executed tests from reported CI or static review.
4. Report actionable findings ordered P0–P3 with file/line, triggering condition, user impact and suggested direction. Separate missing requirements, unverified risks and optional polish from demonstrated defects.
5. Summarize acceptance coverage, test evidence tied to the head SHA, manual iPhone checks, and a recommendation: ready for owner review, changes required, or insufficient evidence. No merge, edits or publication in review-only work.
