# PulseMesh portfolio roadmap

Baseline reviewed on November 17, 2026. Repository roadmap published on November 18, 2026.

This roadmap applies to this repository and follows the shared Null Catchers portfolio plan. Verify the documented state against the current code and runs before starting work.

**Estimated initial demo effort** 35–55 hours for a developer familiar with the project. The estimate excludes external reviews, store accounts, target environment setup, and later milestones.

## Project priorities

**Documented state** The app supports durable realtime messaging, journal and cursor reconciliation, offline Flutter, attachments, notifications, and mesh WebRTC. The encryption protocol or provider interface does not establish a completed Signal integration or cryptography audit.

**P0 — Demo** Recover an offline message and sync it exactly once to a second session. Use existing duplicate and ordering tests to identify missing coverage.

**P1 — Validation and depth** Verify a call between two physical devices on separate networks with TURN. Record denied permission and disconnect recovery. Measure message delay and loss with a defined workload, and verify removed users cannot resubscribe.

**P2 — Later** Consider an SFU after measuring the mesh limit. Keep E2EE experimental until a reviewed library and key, device, and recovery flows are validated.

**Acceptance criteria** Offline sends arrive once after reconnect, journal order is restored, rooms stay isolated, and TURN evidence comes from a real call.

**Demo scenario** Send a message with an attachment offline → reconnect → verify delivery → place a short call → verify recovery. [README](https://github.com/The-Null-Catchers/PulseMesh/blob/main/README.md), [Offline Sync](https://github.com/The-Null-Catchers/PulseMesh/blob/main/docs/OFFLINE_SYNC.md), [WebRTC](https://github.com/The-Null-Catchers/PulseMesh/blob/main/docs/WEBRTC.md).

## Next milestones

The [offline sync guide](docs/OFFLINE_SYNC.md) explains SQLite, the persisted client ID, cursors, and server acknowledgement.

1. [ ] Use two accounts and two rooms. Queue a message offline, close and reopen the app, and confirm it remains pending.
2. [ ] Reconnect and check event order and message IDs. Confirm one message appears for sender and recipient and that room contents remain separate.
3. [ ] Capture pending, acknowledged, and failed states from a known release. Record the device and explain what a server acknowledgement means.

## Portfolio acceptance checklist

- [ ] Another person can reproduce the primary workflow from a clean checkout using the README and test credentials or fixtures.
- [ ] The demo tells one complete story with a defined user, problem, and saved result.
- [ ] Tests cover the main flow, an important failure, and access boundaries when multiple accounts are involved.
- [ ] Demo data is labeled synthetic and reproducible. Review screenshots and recordings for secrets and customer data.
- [ ] Include four to six real screenshots where appropriate, a 60–120 second recording, and working links. Identify the revision used for capture.
- [ ] The README describes implemented capabilities, setup, architecture, limits, tests, and the demo.
- [ ] A short case study explains two engineering decisions, a considered alternative, and how the system handles an actual failure.
- [ ] Release evidence records the commit SHA, CI, prerequisites, and limits. Performance data includes workload, hardware, and method.
- [ ] Licensing and contributor attribution are settled before distribution. Choose the license for each repository individually.

A hosted demo is optional. Code execution, server administration, and secret management can be demonstrated through a recording and a reproducible isolated environment. Keep public demo access scoped to the activities it needs.

## Implementation and follow-up

- Break P0 into tasks with expected behavior, acceptance criteria, and a suitable test.
- Verify existing functionality first. Update this plan when evidence tied to a commit or PR closes a milestone.
- Record the fixture source, the revision used for evidence, and the tested limits.
- Review the final diff and verify required checks for its exact SHA before merging. Follow branch protection.
- For documentation-only changes with no applicable workflow, verify content and links and record the checks actually performed.
- Tie performance, security, and readiness claims to supporting evidence.
