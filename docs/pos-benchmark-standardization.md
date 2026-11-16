# POS Benchmark and Standardization Plan

Branch: feat/pos-benchmark-standardization

## Goal
Raise AALA POS toward a dependable, low-cost, offline-first restaurant POS for small and mid-sized Indian highway hotels (roughly 10–20 outlets in the initial target), using independently implemented workflows informed by public product documentation, lawful demos, and customer-authorized testing. This is a benchmark and implementation plan, not a promise of feature parity.

## Reference platforms (15)
1. Petpooja
2. Restroworks (formerly POSist)
3. GoFrugal
4. Rista / DotPe
5. UrbanPiper
6. SlickPOS
7. TMBill
8. Torqus
9. LimeTray
10. eZee Optimus
11. Foodics
12. Toast
13. Square for Restaurants
14. Lightspeed Restaurant
15. Restrofi

## Evidence rules
- Public vendor pages, published help material, official app listings, and openly available demos are acceptable evidence.
- Deeper app inspection must use an APK/account/device supplied by the user or otherwise lawfully authorized for testing.
- Do not bypass authentication, payment controls, DRM, API access controls, or vendor terms.
- Do not copy proprietary source code, assets, branding, or confidential workflows. Reimplement generic POS capabilities independently.
- Mark every finding as verified, vendor-claimed, observed in authorized test, or unknown. Never infer that an unobserved feature is absent.

## Initial benchmark dimensions
| Area | Behaviours to benchmark |
|---|---|
| Order entry | Dine-in, takeaway, delivery, counter sale, quick repeat, item notes, modifiers, variants, combos |
| Tables | Areas, table map, merge/split, transfer, running orders, occupancy and waiter assignment |
| KOT/KDS | Station/category routing, multiple printers, reprint, cancel/void trail, bump/recall, preparation status |
| Billing | GST, discounts, service charge, split/merge bills, partial payments, refunds, hold/resume, print and WhatsApp share |
| Offline | Create orders and bills offline, local durability, conflict handling, safe retry, reconnect sync and duplicate prevention |
| Roles | Owner, manager, counter, waiter, kitchen, partner; granular permissions and audit trail |
| Inventory | Ingredients, recipes/BOM, units and conversions, purchase, wastage, stock count, low-stock, FIFO/weighted costing |
| Reports | Day close, sales by item/category/payment/staff, tax, voids, inventory consumption, exportable PDF/CSV |
| Integrations | QR menu/order, WhatsApp bill, payment devices, delivery aggregators, accounting/export APIs |
| Multi-outlet | Outlet isolation, central menu, pricing, users, consolidated reports and controlled transfers |
| Reliability | Startup speed, crash recovery, printer reconnect, backup/restore, data export and migration |
| UX/accessibility | Large touch targets, Hindi/English labels, low-end Android, fast search and minimal taps |

## AALA repository baseline (initial inspection)
- Flutter app, package name hotel_pos, version 1.0.6+6.
- lib/main.dart is approximately 198 KB and contains a large amount of application code; refactoring must be incremental and must not destabilize existing flows.
- Existing dependencies include Supabase, SQLite (sqflite), shared preferences, Bluetooth thermal printing, PDF, sharing, QR, TTS and charts.
- Root also contains lib/screens, lib/services, lib/models, lib/Data, supabase, python_intelligence, test, and .github.
- The app describes itself as zero-cost and offline-first. Benchmark work must preserve this direction and avoid introducing paid services without approval.

## 48-hour delivery target (realistic)
### Phase 1 — Baseline and evidence
- Map current screens, services, data models, Supabase schema/functions, offline queue/sync and tests.
- Create a workflow-by-workflow gap matrix against the benchmark dimensions.
- Identify critical defects and duplicate/fragile logic before changing architecture.

### Phase 2 — Highest-value improvements
Prioritize only issues confirmed by code inspection and reproducible tests:
1. Order lifecycle and KOT correctness.
2. Final bill actions: print, WhatsApp send, and print + WhatsApp send.
3. Offline-safe order/bill persistence and idempotent sync.
4. Role-based access and auditability.
5. Inventory/report accuracy where the existing schema supports it.

### Phase 3 — Verification
- Run formatting, static analysis and automated tests.
- Build an APK from the exact feature-branch commit through the existing GitHub Actions workflow.
- Provide a test checklist and list any unverified items.
- Keep changes in a ready-for-review PR; do not merge into production without validation.

## REA integration boundary
REA is an agent-connected, local reverse-engineering toolkit. Its published workflow requires installation and explicit local setup, and its Android APK analysis uses JADX. Its website observation mode is documented as passive capture/inspection, not general-purpose browser automation. This ChatGPT GitHub connection can inspect and edit repository files, but it cannot install REA on the user's Android device or capture competitor app sessions from this repository alone.

To perform authorized deep app comparisons, provide the relevant vendor demo APKs, screen recordings, or test credentials/device access with permission. Until then, benchmark public evidence and AALA's own code; mark competitor-specific implementation details as unknown.

## Acceptance criteria
- No production branch changes during the benchmark.
- No unverified claims of competitor feature parity.
- No secrets, customer data, or real payment credentials committed.
- All code changes accompanied by tests or a documented manual test.
- CI/APK build tied to the exact commit under test.
- Offline billing remains usable without internet; reconnect does not duplicate orders or payments.
