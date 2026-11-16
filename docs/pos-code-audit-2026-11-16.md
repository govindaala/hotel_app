# AALA POS repository audit — 2026-11-16

Branch: `feat/pos-benchmark-standardization`

## Scope and evidence

This is a static repository audit of the Flutter source and checked-in Supabase migrations. It is not a device test, a production database inspection, or a competitor APK reverse-engineering report.

Public reference material reviewed so far:
- Petpooja public demo: https://www.youtube.com/watch?v=1pSi_-hZQ6w
- Petpooja billing demo: https://www.youtube.com/watch?v=NXwNEEO1L7o
- TMBill full product walkthrough: https://www.youtube.com/watch?v=8cwGJ7VmHZA
- TMBill support/training videos: https://www.tmbill.com/tmbill_support_videos
- SlickPOS public demo channel: https://www.youtube.com/channel/UCG99NhWXTYJdrZm5gePFMXA
- Square for Restaurants training demos: https://squareup.com/us/en/square-university/restaurants
- Restroworks product overview: https://www.restroworks.com/
- eZee Optimus demo: https://ezeeoptimus.com/ycdemo/
- Toast product demo: https://pos.toasttab.com/demo
- Lightspeed Restaurant demo: https://www.lightspeedhq.com/pos/restaurant/

The list of 15 products in `pos-benchmark-standardization.md` is the research scope, not a claim that all 15 have been deeply inspected. Public video/page evidence can establish visible workflows or vendor claims only. Backend guarantees, failure handling, and hidden functionality remain unknown without authorized test access.

## Confirmed AALA code observations

| Area | Observation | Assessment |
|---|---|---|
| App architecture | Flutter app, package `hotel_pos`; the main entry file is about 198 KB. | High coupling risk; refactor in small tested slices. |
| Receipt | `lib/receipt_generator.dart` creates a Hindi receipt image and embeds it in a PDF. | Existing receipt generation; test long item names, large orders, 58/80 mm widths and missing profile fields. |
| Final bill actions | The final-bill dialog offers print, WhatsApp PDF, and print + WhatsApp. | The WhatsApp branch calls `Share.shareXFiles`, which opens the generic Android share sheet. It does not target the entered number or prove WhatsApp delivery. |
| Customer fields | The app sends customer name/phone in the settlement RPC payload. A later migration adds both invoice columns and writes them. | Source migration supports persistence; verify that all deployed environments have applied the later migration. |
| Settlement | `settle_hotel_order` uses a unique `(store_code, bill_no)` index and inserts invoice/items/ledger data in one transaction. | Good atomicity/idempotency for a repeated bill number. The client currently generates a new millisecond-based bill number for each checkout attempt, so retry after an ambiguous network timeout is not guaranteed to reuse the same key. |
| KOT lifecycle | Settlement updates matching table KOTs to `settled`. | Verify multiple active KOTs, split/partial settlement and parcel edge cases with regression tests. |
| Offline persistence | `OfflineDatabase` provides a durable SQLite operation queue with UUID IDs, store scoping, attempts and error text. | Queue implementation exists; this audit has not yet established that the entire order-to-invoice settlement path is queued and replayed offline. Do not advertise full offline billing until proven. |
| Automated tests | Current visible Dart tests cover LAN authorization, line JSON protocol, offline database and report validation. | No settlement/receipt/WhatsApp integration test was found in the inspected test directory. |
| APK workflow | `.github/workflows/build_akp.yml` builds on PRs targeting main/master and on selected push branches; it also supports manual dispatch. | PR to main should trigger the existing build. Feature-branch push alone is not in the push branch allowlist. |

## Highest-priority engineering work

1. Make bill creation retry-safe by persisting a stable checkout/bill operation ID before the RPC and reusing it after timeout/restart. Do not generate a fresh bill number for a retry of the same checkout.
2. Make WhatsApp behavior honest and useful: either target the selected customer and attach the PDF using a maintained Android-compatible integration, or clearly present a share sheet and tell the cashier to choose WhatsApp and confirm the recipient. Never claim the PDF was delivered merely because a share intent returned.
3. Add automated tests for settlement payloads, repeated settlement, customer contact persistence, receipt generation and share failure handling.
4. Prove offline order/KOT/settlement behavior end-to-end before calling the product offline-first for billing.
5. Add reconciliation/reporting checks so a settled invoice, invoice items, cash/UPI ledger and KOT status cannot silently diverge.

## Release guardrails

- Keep all changes on the feature branch until reviewed.
- Do not alter production Supabase data or apply migrations remotely as part of static inspection.
- Do not change workflow permissions/secrets or bypass CI.
- Run tests and build an APK for the exact reviewed commit.
- Test on a physical Android device, thermal printer and WhatsApp before calling the WhatsApp path verified.
