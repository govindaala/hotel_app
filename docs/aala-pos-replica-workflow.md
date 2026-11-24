# AALA POS: Replica-skill workflow adaptation

**Status:** adopted as a working method; this document is not a claim that AALA is feature-complete.  
**Source method:** https://github.com/Jakeschincariol/replica-skill (MIT).  
**Target:** the existing Flutter Android application in this repository, not a new web app.

## Why we are adapting rather than copying the pack

Replica-skill provides a useful sequence: recon -> architecture -> design -> build -> backend -> test -> diff -> user-feedback research. Its examples assume a generic app and often use web tooling (for example Playwright, HTML semantics, Tailwind and Stripe). AALA is a Flutter + Supabase + SQLite/SharedPreferences Android POS. We will retain the evidence discipline and clean-room workflow, but use Flutter-native implementation and tests.

This file is an execution contract. It must lead to working, tested app changes; updating this file or the matrix alone does not count as product progress.

## Adapted skill map

| Replica skill | AALA adaptation | Output / done condition |
|---|---|---|
| replica-recon | Inventory AALA screens, actors, state transitions and end-to-end hotel workflows; benchmark public vendor material and only authorized demos | Screen/flow map and evidence-linked feature matrix |
| replica-architect | Document current Flutter, Supabase RPC/RLS, SQLite queue, LAN and printer boundaries before changing them | Data ownership, sync and transaction contracts; no speculative rewrite |
| replica-design | Review Flutter widgets, spacing, typography, loading/empty/error/disabled states, accessibility and Hindi readability | Reusable Flutter component improvements with widget tests |
| replica-build | Implement one vertical slice at a time in the existing app | Real feature code, acceptance tests and a reviewable feature-branch PR |
| replica-backend | Adapt to Supabase/Postgres and existing RPCs; no Stripe/Next.js assumptions | Reviewed SQL/RPC and RLS design plus cross-store tests; production migrations are not applied by this workflow |
| replica-test | Replace Playwright with flutter_test, integration_test and authorized device/manual checks | Reproducible test cases, actual command output and bug severity |
| replica-diff | Use a feature matrix and same-state screenshots; compare behavior, not brand assets | Honest coverage report and ordered missing-work list |
| replica-entrepreneur | Read public customer feedback where terms permit; preserve source links and sample counts | Evidence-backed usability improvements, not invented review trends |
| replica-brand / launch / deploy | Not part of current engineering scope | Defer until core POS reliability and product readiness are demonstrated |

## Evidence rules

Every benchmark statement must carry:
- product and exact feature/workflow;
- source URL and access method (vendor documentation, public walkthrough, or vendor-authorized demo);
- date checked and version/build when known;
- evidence class: vendor_claim, public_demo_observed, or independently_verified;
- exact observed behavior and limitations;
- proposed AALA acceptance criterion.

A vendor feature page is not proof that the feature works in production. A screenshot is not proof of a complete workflow. Reading REA or Replica documentation is not reverse engineering. Never mark a competitor demo, APK inspection or AALA runtime test complete unless it actually happened.

## AALA implementation and test rules

1. Preserve the existing Flutter architecture unless evidence demonstrates a specific reason to change it.
2. Implement generic POS functionality independently. Do not copy competitor code, assets, logos, text, private APIs or protected UI.
3. Work only on a dedicated feature branch. Do not push or merge directly to main.
4. Prioritize data correctness and safety: tenant isolation, duplicate billing/ledger effects, stock correctness, offline recovery, order/KOT lifecycle, permissions, then usability and optional features.
5. For every bug fix, write or identify a failing regression test first where practical; make the smallest coherent correction; run the narrow test and relevant regression suite.
6. Use flutter_test for unit/widget tests and integration_test for end-to-end device flows. Do not add Playwright to this Flutter app.
7. The Android build workflow currently builds and uploads an APK but does not itself run flutter analyze or flutter test. Do not interpret a successful APK build as proof that app behavior is correct.
8. Record commands actually executed, their exit status and any unavailable runtime/device dependencies. Never report a test as passed if it was not run.
9. Do not apply production schema/data changes, change workflow YAML/secrets/permissions, or add paid services as part of this adaptation.

## First vertical slice: counter/table order -> kitchen -> settlement

This is the first product path to make reliable before expanding feature breadth.

### Current source-level observations (not device-verified)

- Counter checkout has an in-memory duplicate-submit guard: _processCheckout returns when _isProcessingCheckout is already true.
- Counter/table order creation can queue a KOT locally when the cloud insert fails.
- Direct counter billing calls settle_hotel_order; a failed RPC currently reaches the outer error handler rather than a durable final-invoice queue.
- Table settlement creates a millisecond-based bill number inside the submit attempt. A retry after an ambiguous timeout can therefore use a new bill number; a server-side unique key on (store_code, bill_no) alone does not make that retry idempotent.
- The current offline replay path has been source-audited for KOT create/update and counter-inventory updates; final invoice/payment settlement is not yet established as a replayable queue operation.
- These are static-source findings. No live Supabase transaction, production schema, physical printer, or Android device flow was exercised in this audit.

### Required acceptance criteria

| ID | Acceptance criterion | Required verification |
|---|---|---|
| POS-01 | A cashier cannot submit the same in-progress checkout twice from rapid taps | Flutter widget test |
| POS-02 | A checkout operation has one durable identity and immutable payload across retries/restarts | Unit + SQLite persistence tests |
| POS-03 | An ambiguous server timeout followed by retry creates exactly one invoice and one ledger effect | Supabase/Postgres integration test against an isolated test project/database |
| POS-04 | A KOT created offline is visible as pending and synchronizes once after reconnect | SQLite queue test + device integration test |
| POS-05 | Final invoice/payment is never silently described as saved when only a KOT was queued | Unit/widget tests and manual flow |
| POS-06 | Stock is decremented exactly once and is reconciled after retry/reconnect | Database integration + offline replay tests |
| POS-07 | Table, parcel and direct-counter paths preserve the correct source, table, cashier, items and payment mode | Flow-level integration tests |
| POS-08 | A second store cannot read or mutate the first store's records | RLS tests with two authenticated store identities |

**Do not implement POS-02/POS-03 with a superficial timestamp change.** The operation ID must be persisted before the request, reused after ambiguous failure and bound to the immutable checkout payload. The server transaction must deduplicate the operation and all invoice/ledger side effects atomically.

## First-pass benchmark matrix

See aala-pos-feature-matrix.csv. Its initial statuses deliberately distinguish source-level presence, confirmed gaps and unverified behavior. Do not calculate a parity percentage until each benchmark feature is tied to a named product and an evidence record.

## Completion reporting

Every implementation batch must report:
- branch, commit and PR URL;
- exact files changed and user-visible behavior changed;
- regression tests added;
- exact test/analyzer/build commands and pass/fail/not-run results;
- unresolved risks and next smallest buildable slice.

A documentation-only change is not a completed POS feature. The product goal is a reliable installable POS, not a larger research folder.
