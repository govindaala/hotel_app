# REA-driven restaurant POS reverse-engineering tracker

**Last updated:** 2026-11-23 15:53 IST  
**AALA repository baseline:** `main` at `c52ed32ce365db9b2b27fc02d92fbad2a61570de`  
**Purpose:** Maintain an evidence-led, lawful comparison of restaurant POS workflows and turn verified findings into small, independently implemented AALA improvements. This is a research tracker, not a feature-parity claim or market-share ranking.

## 1. Canonical REA project and current capabilities

Canonical project re-verified on 2026-11-20:

- Repository: [morluto/rea](https://github.com/morluto/rea)
- Repository name/title: `rea` / **REA: Reverse Engineer Anything**
- Owner: `morluto`; default branch: `main`; latest release commit checked today: `8bb01b514ac766c0c3ecc8f362bd38186eaec9c2`
- Latest published release observed: [rea-agents 6.10.1](https://github.com/morluto/rea/releases/tag/rea-agents-6.10.1), published 2026-11-20. Release 6.10.0 (also 2026-11-20) adds more offline artifact/format inspection families, including Android boot-image and OTA payload inspection; 6.10.1 fixes a Kuna serial job-count constant.
- License: [MIT](https://github.com/morluto/rea/blob/main/LICENSE). Third-party engines retain their own licenses and terms.
- Package: [rea-agents](https://www.npmjs.com/package/rea-agents), version 6.10.1; required Node range: `^22.23.4 || ^24.22.1 || >=26.12.1`.

### Relevant analysis families

| REA family | What it can establish | Requirements / limits |
|---|---|---|
| Android APK / JADX | Static package/manifest facts, class and method inspection, direct DEX references | Node.js per package engine; full JDK 17+; caller-supplied JADX headless MCP 0.7.1 JAR, SHA-256 pinned in REA; Linux also needs procps-compatible `ps`. It does **not** execute the APK, validate signatures, handle split APK/AAB as a single APK, or capture Android runtime behavior. |
| Flutter APK | Pure parsing of APK, Dart VM snapshot hashes, per-ABI library digests, engine build IDs and bounded string-pool projections | No Flutter engine or decompiler required. It does not deserialize Dart objects or recover complete typed Dart source/classes/functions; string-pool tokens are partial projections. |
| Android resources / Apktool | Decoded Android resources and binary manifest through the caller-selected Apktool launcher | Apktool 2.7.0+ and a Java runtime; REA does not install them. |
| Browser / web app | Page structure, scripts, browser/network observations and requested screenshots | Chrome-family browser and an explicitly authorized target/session. Browser observation is not proof of native-app behavior. |
| Runtime / process / device workflows | Selected process, application or device observations | Operation-specific host tools and authority; execution, network and device actions can affect state. Review each operation before use. |

Primary REA documentation:
- [README and supported target matrix](https://github.com/morluto/rea)
- [Installation and runtime requirements](https://github.com/morluto/rea/blob/main/docs/getting-started/installation.md)
- [Android/JADX analysis](https://github.com/morluto/rea/blob/main/docs/guides/android/android-analysis.md)
- [Flutter APK analysis](https://github.com/morluto/rea/blob/main/docs/guides/android/flutter-analysis.md)
- [Apktool resource analysis](https://github.com/morluto/rea/blob/main/docs/guides/android/apktool-resource-analysis.md)
- [CLI and Evidence](https://github.com/morluto/rea/blob/main/docs/getting-started/cli.md)
- [Security boundary](https://github.com/morluto/rea/blob/main/SECURITY.md)
- [Responsible-use disclaimer](https://github.com/morluto/rea/blob/main/DISCLAIMER.md)

### Execution readiness checked on 2026-11-20

- Available Node.js remains `v22.16.0`, below REA 6.10.1's minimum supported Node version `22.23.4`; npm is `10.9.2`.
- `rea`, `adb`, `emulator`, `apktool`, JADX, Flutter and Dart are not installed in this execution environment. No local AALA APK file or Android device/emulator is available here.
- REA's package/docs were inspected from the public GitHub repository. The REA CLI was **not** installed or executed in this run; npm installation was not attempted again while the current Node runtime is outside the supported range.
- No competitor APK, vendor-authorized demo account or public demo session was supplied/available.

**Execution result:** current repository, README, package metadata, installation, Android/JADX, Flutter AOT, CLI, MIT license, SECURITY and DISCLAIMER material were studied. Actual REA analysis of AALA or a competitor app was **not** performed. Do not count documentation research as reverse engineering. First restore a supported Node runtime and install the local REA package; add JDK 17+ plus the pinned JADX bridge only for Java/Kotlin class/method analysis. Flutter APK identification needs no decompiler but still requires an actual APK file. Competitor workflow observation requires lawful public/vendor-authorized access and a suitable device/session.

## 2. Competitor target shortlist and coverage

This is a working shortlist of India-focused restaurant POS products plus two adjacent order-integration platforms. It is not a ranking. All entries below are **vendor-published claims** from public pages; no live demo or app workflow has yet been independently observed with REA.

| # | Product / target | Public source reviewed | Publicly described areas to inspect | Evidence today | REA app inspection |
|---:|---|---|---|---|---|
| 1 | Petpooja | [Offline POS](https://www.petpooja.com/offline-pos) | On-premise/offline billing, KOT, QR ordering, KDS, multi-outlet operations | Vendor claim; public webpage, 2026-11-18 | Pending |
| 2 | GoFrugal Restaurant POS | [Restaurant POS](https://www.gofrugal.com/restaurant/restaurant-pos-software/) | Offline billing, table management, KOT/KDS, recipes/BOM, inventory and wastage | Vendor claim; public webpage, 2026-11-18 | Pending |
| 3 | Restroworks | [Official platform](https://www.restroworks.com/) | POS/table management, kitchen routing, recipe/ingredient inventory, QR/kiosk, analytics | Vendor claim; public webpage, 2026-11-18 | Pending |
| 4 | Rista by DotPe | [Restaurant management](https://dotpe.in/rista-restaurant-management-software.html) | Mobile/cloud POS, order lifecycle, table occupancy/reservations, QR, aggregator integrations | Vendor claim; public webpage, 2026-11-18 | Pending |
| 5 | PosBytz | [Restaurant POS features](https://posbytz.com/en/restaurant/features/) | Offline sync, table/waiter/QR flows, purchase/GRN, recipes, CRM and accounting | Vendor claim; public webpage, 2026-11-18 | Pending |
| 6 | TMBill | [Official platform](https://www.tmbill.com/) | Split bills, taxes/payment modes, KOT/KDS, inventory, QR, CRM, accounting and order flow | Vendor claim; public webpage, 2026-11-18 | Pending |
| 7 | eZee Optimus | [Official product site](https://www.ezeeoptimus.com/) | Dine-in/takeaway/room service, waiter app online/offline, back office, multi-language | Vendor claim; public webpage redirects to Yanolja Cloud Solution, 2026-11-18 | Pending |
| 8 | SlickPOS | [Official product site](https://slickpos.com/) | POS, online orders, kitchen print/display, waiter app, inventory/recipe, reports, outlets | Vendor claim; public webpage, 2026-11-18 | Pending |
| 9 | UrbanPiper Hub | [India product page](https://www.urbanpiper.com/in/hub) | Aggregator order intake, menu management, order tracking, stock and reporting | Vendor claim; adjacent integration platform, not a full POS comparator; 2026-11-18 | Pending |
| 10 | LimeTray | [Restaurant POS](https://limetray.com/restaurant-pos) | POS/offline mode, customer/CRM integration, analytics and aggregator order consolidation | Vendor claim; public webpage, 2026-11-18 | Pending |
| 11 | Restrofi | [Official platform](https://restrofi.com/) | QR ordering, KDS, GST, recipe costing, staff roles/PINs, offline counter billing | Vendor claim; public webpage, 2026-11-18 | Pending |
| 12 | RestroPod | [Official platform](https://restropod.com/) | Offline billing, local encrypted data, tables/KOT, recipes/stock and QR | Vendor claim; public webpage, 2026-11-18 | Pending |
| 13 | DinePluz | [Official platform](https://dinepluz.com/) | POS, table management, KOT/KDS, captain app, QR ordering, GST and thermal printing | Vendor claim; public webpage, 2026-11-18 | Pending |
| 14 | Vemo | [Official platform](https://www.vemohq.com/) | POS, KOT/KDS, inventory/food-cost workflows and offline-first operation | Vendor claim; public webpage, 2026-11-18 | Pending |
| 15 | NamastePOS | [Official platform](https://namastepos.in/) | Offline-first billing/KOT, GST, QR, loyalty, WhatsApp receipts, inventory/costing and reservations | Vendor claim; public webpage, 2026-11-18 | Pending |

### Focused vendor-source review — 2026-11-20

The following official public sources were checked today. These are **vendor claims**, not observed application workflows:

| Target | Source and access method | Claims described by the source | Evidence strength / AALA usefulness |
|---|---|---|---|
| Petpooja | [Restaurant billing POS](https://www.petpooja.com/poss/restaurant-billing-software); public official webpage, checked 2026-11-20 | Three-click billing, configurable bills, multi-terminal/master-station setup, table/area management, station-wise KOT printers, taxes/discounts and offline/cloud operation | Vendor claim only. Useful questions for AALA: local master/terminal topology, KOT printer routing and offline bill recovery; no sync/idempotency behavior was verified. |
| Petpooja | [How the Bridge Server Works Inside POS Local](https://blog.petpooja.com/industry-business-guides/bridge-server-works-inside-pos-local/); official vendor blog dated 2026-07-08, checked 2026-11-20 | Describes local storage of bills/KOT/reports/customer records, LAN-connected billing/KDS/captain devices, cloud-to-local menu/order sync, claimed operation for up to five days without internet in a split-server setup, and scheduled backups | Vendor architecture claim only. Strong design reference for AALA's LAN/offline-first investigation; it does not prove exactly-once replay, conflict handling or the five-day claim independently. |
| Petpooja | [Online Order Management](https://www.petpooja.com/poss/online-order-management-software); public official webpage, checked 2026-11-20 | Aggregated online orders, stock-based menu availability, menu sync and online-order reconciliation reporting | Vendor claim only. Useful as a future menu-availability and payout/commission reconciliation benchmark; no live aggregator integration was tested. |
| TMBill | [Official platform](https://www.tmbill.com/); public official webpage, checked 2026-11-20 | Describes a QR/kiosk-to-POS-to-KOT/KDS-to-payment/settlement flow, split bills, offline operation, recipe-linked stock, low-stock alerts, QR ordering, CRM and reports | Vendor-described workflow only, not a public demo observation. Useful to frame acceptance tests around order routing, split tender/settlement and stock deduction; no correctness or offline recovery was verified. |
| Restroworks | [Official platform](https://www.restroworks.com/); public official webpage, checked 2026-11-20 | Claims front-of-house POS/table and handheld workflows, operation during connectivity loss, kitchen routing/display, ingredient-level inventory/waste controls and integrations | Vendor claim only. Useful for a future kitchen-routing and inventory evidence checklist; offline behavior and integration depth were not independently tested. |

### Coverage counters

- Working shortlist: **15/15** products recorded in the matrix above.
- Public vendor pages reviewed in the 2026-11-18 shortlist audit: **15/15** (claims only); four focused official pages/articles across three platform groups rechecked on 2026-11-20.
- Public demo workflows actually watched/observed: **0/15**.
- REA static APK inspections: **0/15**.
- REA runtime/device workflow observations: **0/15**.
- Independently verified competitor feature claims: **0**.

UrbanPiper and LimeTray are retained as integration-layer references, not treated as equivalent full POS products. If a public page is unavailable, outdated, redirected or only describes a legacy product, retain that caveat rather than inferring current functionality.

### Standard evidence record required for every future observation

Record: target/version/build if known; exact feature question; source URL; access method (public page, public demo/video, vendor-authorized APK/account/device); inspection date; REA command/tool and input digest where applicable; observed behavior; source Evidence ID or screenshot/recording reference; coverage/limitations; evidence strength (`vendor claim`, `public demo observed`, or `independently verified`); AALA relevance; proposed acceptance criteria. Never infer an unobserved feature is absent.

## 3. AALA baseline and confirmed reliability gaps

Static source inspection of current `main` at `13bf76ca7f93619de2ca4e42780bc1a21e9a9e1e` (2026-11-20) confirms:

1. **P1 — checkout retry is not durable-idempotent.** Table settlement creates a new timestamp bill number inside each `completeSettlement` attempt in [lib/main.dart](../lib/main.dart#L2174-L2233). Direct counter sale does the same in [counter_sale_screen.dart](../lib/screens/admin/counter_sale_screen.dart#L557-L596). The SQL migration adds a unique `(store_code, bill_no)` index and handles a repeated identical bill number, but a retry after an ambiguous timeout gets a new bill number. If the first transaction committed and the response was lost, a second invoice and `daily_expenses` CASH_IN row can be created. A correct fix needs a durable per-checkout operation ID persisted before the RPC and reused across retries/restarts in both flows, plus regression tests. Do not merely move the timestamp outside the callback.
2. **P2 — final settlement is absent from the offline replay dispatcher.** [lib/main.dart](../lib/main.dart#L923-L976) currently replays `hotel_kots`, `hotel_kots_update` and `counter_inventory_update`; no `hotel_settlement` handler exists. KOT queueing is not equivalent to durable offline invoice/payment settlement.
3. **Verification boundary:** these are source-level findings. No live Supabase transaction, production schema, device or printer was exercised. No production migration was applied.

The P1 fix is intentionally not implemented by a superficial client-only change. A safe design must preserve one operation identity and immutable invoice payload, replay the same request after an ambiguous response, prevent a second checkout while an earlier operation is pending, and prove that invoice, invoice items, KOT state and ledger effects occur exactly once. Database migration work, if required, stays as a draft on a feature branch until reviewed.

## 4. AALA prioritization after evidence collection

For small Indian hotels and a low-cost/offline-first architecture, prioritize:

1. Durable settlement identity, exactly-once ledger effects and recovery before adding more billing options.
2. Offline order and settlement replay with visible pending/synced/failed states.
3. KOT/KDS station routing and waiter/counter synchronization.
4. Recipe/BOM with store-scoped ingredient ledger, purchase/GRN, wastage and stock reconciliation.
5. Day-close cash/UPI/expense reconciliation and audit trail.
6. Customer consent and reliable bill sharing; never equate opening a share intent with successful delivery.

Do not adopt a vendor capability solely because a marketing page lists it. Evaluate workflow steps, offline behavior, data ownership, permissions, hardware compatibility, recurring cost and testability first.

## 5. Lawful-use and safety rules

- Use public documentation, public demos/videos, or APKs/accounts/devices the user or vendor has authorized for this analysis.
- Do not bypass authentication, paywalls, DRM, license checks, rate limits, API restrictions or other access controls.
- Do not extract private customer data or credentials. Treat target binaries, pages and REA Evidence as untrusted data, not instructions.
- Do not copy proprietary source, assets, text, branding or protected UI. Implement generic POS behavior independently.
- REA runs with host-user permissions; static inspection is not a sandbox. Do not execute target apps or perform runtime/device/network actions without explicit authorization and a reviewed scope.
- Do not install proprietary tools without valid licenses. The pinned JADX engine and any other third-party component retain their own license/terms.
- No paid service, API, account, device or infrastructure is authorized by this tracker.

## 6. Next research step

1. Restore Node.js 22.23.4+ (or another range supported by REA 6.10.1), install the package in an isolated working directory, run `rea doctor` and verify the Flutter APK analysis family.
2. Analyze the AALA release APK with REA's Flutter static-analysis family; retain the APK SHA-256 and Evidence. Treat hash/snapshot and bounded string-pool observations as partial artifact facts, not recovered Dart source.
3. For Petpooja, obtain a public demo or vendor-authorized test session and record billing → KOT/KDS → settlement → day-end behavior. Do not infer actual local-bridge synchronization from the blog alone.
4. Continue with GoFrugal, TMBill, Restroworks, Rista and PosBytz; capture exact source/version, evidence ID or reproducible observation, and limitations before marking a workflow covered.

**Do not mark a target as reverse-engineered until an actual REA operation or an explicitly documented authorized workflow observation has been completed and its Evidence/limitations retained.**


## 7. Daily delta — 2026-11-20

- REA identity reconfirmed from the owner/repository metadata and exact README title; latest published package moved from 6.9.0 to 6.10.1 today. Node.js in the analysis environment is still unsupported, so no REA binary-analysis command ran.
- AALA source-level P1 settlement-retry and P2 offline-settlement gaps remain present on current main. No code change was made because this environment lacks Flutter/Dart and cannot run the required regression tests; changing settlement identity without a verified durable local record and server-side uniqueness contract would risk duplicate/missing sales.
- The existing evidence-tracker PR is the only open AALA PR observed: [PR #33](https://github.com/govindaala/hotel_app/pull/33). This document update records today's REA release, runtime blocker, focused vendor-source checks and current-main baseline; it does not claim any competitor app was reverse-engineered.
- No authorized competitor APK/demo, device, live printer, or test Supabase instance was available. Public website claims remain vendor claims until independently observed.

## 8. Daily delta — 2026-11-22

### REA repository and execution readiness

- Canonical project reconfirmed from GitHub repository metadata and README: [morluto/rea](https://github.com/morluto/rea), title **REA: Reverse Engineer Anything**, owner `morluto`, default branch `main`, MIT license. The repository describes analysis across applications, binaries and runtime behavior.
- Current REA source `main` HEAD observed today: `7c8493d41d87a5ed29c28b0accd8382d17739d3d`. The latest published package/release is still [`rea-agents 6.10.1`](https://github.com/morluto/rea/releases/tag/rea-agents-6.10.1), published 2026-11-20; the newer GitHub commits have not, by themselves, changed the published npm package version.
- Package metadata still requires Node `^22.23.4 || ^24.22.1 || >=26.12.1`; this execution host has Node `v22.16.0`. REA CLI, ADB, emulator, Apktool, JADX, Flutter and Dart are absent here. No AALA APK or authorized competitor APK/account/device is available.
- [REA PR #13361](https://github.com/morluto/rea/pull/13361) remains open and unmerged. Its proposed Android JADX changes include indexed lookups and a bounded external-caller cache (4,096 entries, with scan fallback when the cap is exceeded). The PR description/comments report regression tests and local validation, but this is **proposed PR code**, not the published 6.10.1 package; do not count it as an available release capability.
- The CLI was not executed and no APK was inspected today. Repository/docs/code study is not app reverse engineering.

### Focused India POS benchmark — official public pages checked 2026-11-22

All observations below are **vendor claims from public official pages**, not REA inspection or independently verified behavior.

| Target / source | Vendor-described workflow or capability | AALA relevance |
|---|---|---|
| [GoFrugal Drive-Thru POS](https://www.gofrugal.com/restaurant/restaurant-pos-software/drive-thru-pos.html) — official public webpage | Describes multi-order kitchen display, QR ordering, CRM/loyalty, mobile waiter operation, recipe management, inventory and extensive MIS reporting. | Turn the claims into test questions for kitchen queue visibility, waiter-to-kitchen handoff, recipe accuracy and store-level reporting; do not assume real-time/offline correctness without observing it. |
| [PosBytz Inventory Management](https://posbytz.com/en/restaurant/features/inventory-management-software/) — official public webpage | Describes purchase/use units and conversions, recipe and semi-finished item mapping, ingredient deduction across order channels, low-stock alerts/PO generation, central-kitchen transfers, stock counts and wastage tracking. | Prioritize auditable unit conversion, per-store recipe deductions, transfer and wastage ledgers before adding broad integrations. |
| [PosBytz KOT Management](https://posbytz.com/en/restaurant/features/kitchen-order-ticket-system/) — official public webpage | Describes KOT generation from several order channels, item/category kitchen routing, modifiers/cancellations, split or partial KOTs, KDS state tracking and offline KOT printing with later sync. | Convert this into regression scenarios for routing, partial fulfilment, cancellation, offline print and duplicate-safe resync. No live printer or offline test was run. |
| [PosBytz Purchase Management](https://posbytz.com/en/restaurant/features/purchase-management/) — official public webpage | Describes vendor/location purchase orders, partial receiving/GRN, expiry/batch tracking, supplier returns and payment records against purchases. | AALA can implement a small, store-scoped PO-to-GRN-to-stock audit trail; avoid adding accounting complexity before ledger correctness is established. |

### AALA status and action

- Remote `main` remains at `13bf76ca7f93619de2ca4e42780bc1a21e9a9e1e`; PR #33 remains open and documentation-only. The research branch remains 13 commits behind current `main`; no automatic rebase or merge was performed.
- Existing source-level risks remain: P1 timestamp-generated bill numbers on retries can permit a second settlement after an ambiguous response; P2 offline replay has no final settlement handler. No live database reproduction was attempted.
- No financial code was changed because the environment lacks Flutter/Dart and cannot run the existing regression suite. A superficial client-only retry change would not establish durable exactly-once invoice/ledger behavior.
- Working shortlist remains 15/15. Public vendor pages were initially surveyed across 15 targets; today's focused detailed source review covered GoFrugal and PosBytz. Public-demo content previously recorded for Petpooja remains page-only. REA static APK inspections: 0/15; REA runtime/device inspections: 0/15; independently verified competitor claims: 0.
- Next: provide a Node version supported by REA 6.10.1 and an AALA release APK for a first local Flutter-APK static analysis; use only public/authorized competitor sessions. In AALA, design durable settlement operation identity and replay tests before implementing a financial transaction change.

### Newly identified P1 — cross-store custom-menu access policy

- Source: [migration `20261105100000_custom_menu_and_kot_ready_metrics.sql`](https://github.com/govindaala/hotel_app/blob/main/supabase/migrations/20261105100000_custom_menu_and_kot_ready_metrics.sql#L15-L22). The table `public.store_custom_menu_items` has RLS enabled, but its policies allow **all** operations for both `anon` and `authenticated` with `USING (true)` and `WITH CHECK (true)`; the migration also grants `SELECT, INSERT, UPDATE, DELETE` to both roles.
- Source: [client initialization and custom-menu calls](https://github.com/govindaala/hotel_app/blob/main/lib/main.dart#L38-L40). The app embeds a `sb_publishable_` key and passes it as Supabase `anonKey`; custom-menu queries additionally filter `store_code` in the client. No Supabase Auth sign-in API usage was found in the repository search; startup restores `is_logged_in`, role, store and staff PIN from local preferences. Client-side `.eq('store_code', ...)` is not an authorization boundary.
- Likely impact **if this migration is present in the live Supabase schema**: a caller using the public publishable key in the `anon` role can read, insert, update or delete custom-menu rows for arbitrary store codes, including item name, price, category and availability. The source repository proves the permissive policy and app client configuration; whether this migration has been applied to production was **not checked**.
- A `sb_publishable_` key is public by design, not a leaked secret. Supabase documents that a publishable key without Supabase Auth uses the `anon` Postgres role and that RLS policies are the row-level security boundary: [Securing your data](https://supabase.com/docs/guides/database/secure-data), [API keys](https://supabase.com/docs/guides/getting-started/api-keys).
- No policy/code change was made: the current app does not establish a Supabase Auth identity in the inspected repository, and simply denying `anon` could break custom-menu cloud sync. A safe fix needs a server-verifiable user/store-membership identity, separate least-privilege table policies and cross-store tests. Do not replace `true` with another client-supplied `store_code` check; that remains forgeable.


## 9. Daily delta — 2026-11-23

### REA source, package and execution readiness

- Canonical repository reconfirmed: [morluto/rea](https://github.com/morluto/rea), README title **REA: Reverse Engineer Anything**, owner `morluto`, default branch `main`, MIT license.
- REA source `main` HEAD: [`ca26f2ac8499fa06af59f2590ec071af8a020094`](https://github.com/morluto/rea/commit/ca26f2ac8499fa06af59f2590ec071af8a020094), committed 2026-11-23 09:41:53 UTC. Latest published npm/release remains [`rea-agents 6.10.1`](https://github.com/morluto/rea/releases/tag/rea-agents-6.10.1), published 2026-11-20. Package metadata declares MIT and Node `^22.23.4 || ^24.22.1 || >=26.12.1`.
- [REA PR #13361](https://github.com/morluto/rea/pull/13361) was merged on 2026-11-22. The source-main change improves Android/JADX class and method indexing, retains raw method identities and adds a bounded external-caller lookup index (4,096 entries, with scan fallback). This is **source-main capability**, not evidence that the older published npm 6.10.1 package contains the merged post-release change.
- Runtime checked in this run: Node `v22.16.0`, npm `10.9.2`, OpenJDK `21.0.12.1`, and `ps` available. Node is below REA's declared minimum. `rea`, ADB, emulator, Flutter, Dart, Apktool and JADX are absent. No APK file or authorized competitor app/device/session is mounted locally.
- The README, package metadata, installation guide, Android/JADX guide, Flutter APK guide, CLI/Evidence guide, SECURITY and MIT LICENSE were read. Flutter APK analysis is pure parsing (snapshot hash, ABI library digests, engine build ID and bounded strings); it does not recover complete typed Dart source or execute the app. Android Java/Kotlin inspection requires the supported REA runtime and the separate JADX engine.
- **Execution result:** no REA CLI command ran; no AALA or competitor APK was inspected. Repository study is not app reverse engineering.

### India POS comparative evidence — 2026-11-23

All evidence remains scoped to public sources. No authentication, paywall, DRM, rate-limit or other access control was bypassed.

| Target | Source / access method / date | Evidence strength and observed material | AALA usefulness / limit |
|---|---|---|---|
| TMBill | [Public browser POS demo](https://www.tmbill.com/resources/free-pos-demo/), opened in browser 2026-11-23 | **Public demo observed — limited initial view.** The page exposes a Master POS, OrderFlow Captain app and KDS demo; it describes table selection, dine-in/pickup/delivery/quick bill, saving a KOT and moving it to Served. The page explicitly says the demo is simplified, sample menu/prices are used and nothing is sent anywhere. Demo buttons were not exercised. | Useful acceptance-flow reference for Captain → POS → KOT → KDS → Served and role/device hand-off. It does not prove real backend sync, payments, offline behavior or production correctness. |
| Petpooja Offline POS | [Official Offline POS page](https://www.petpooja.com/offline-pos), public webpage read 2026-11-23 | **Vendor claim.** Describes a local Bridge Server holding bills, KOTs, dine-in/takeaway orders and reports; menu/prices/settings and online orders sync from cloud; lists Captain, QR and KDS add-ons and local backup. | Useful architecture question for a small outlet: a local authoritative store plus LAN clients and controlled cloud replication. The advertised offline duration/sync and backup behavior were not independently tested. |
| Petpooja KDS | [Official KDS page](https://www.petpooja.com/poss/kitchen-display-system), public webpage read 2026-11-23 | **Vendor claim.** Describes Android/Windows KDS, multiple cooking stations, station-wise running orders, individual KOTs plus aggregated item lists, ready status and item out-of-stock updates. | AALA acceptance tests should cover station routing, partial item readiness and availability feedback to waiter/counter. No live KDS or hardware was tested. |

Coverage counters after today's limited public-demo inspection:

- Working shortlist: **15/15** (Petpooja, GoFrugal, Restroworks, Rista, PosBytz, TMBill, eZee Optimus, SlickPOS, UrbanPiper, LimeTray, Restrofi, RestroPod, DinePluz, Vemo, NamastePOS).
- Public vendor-page survey: **15/15** (claims only).
- Public demo pages inspected: **1/15** (TMBill initial browser demo only; no interactive flow completed).
- REA static APK inspections: **0/15**.
- REA runtime/device workflow observations: **0/15**.
- Independently verified competitor feature claims: **0**.

### AALA repository, workflow and audit delta

- AALA `main` is now `c52ed32ce365db9b2b27fc02d92fbad2a61570de`. Compared with the prior recorded baseline `13bf76ca7f93619de2ca4e42780bc1a21e9a9e1e`, five commits add/change only `docs/rea-pos-reverse-engineering-tracker.md`; no app source changed. PR [#33](https://github.com/govindaala/hotel_app/pull/33) merged 2026-11-23 01:13:27 UTC. No open PRs were returned by the repository API. Local working-tree status remains unavailable because no repository checkout is mounted in this environment.
- Latest PR workflow [#293](https://github.com/govindaala/hotel_app/actions/runs/45008902461) succeeded on `research/rea-pos-coverage-2026-11-18`, SHA `4f9e19fe34903fe0f8511846f161bc0ff4281807`; APK artifact `AALA-POS-293` uploaded, release step skipped as expected for a PR.
- Latest Push workflow [#294](https://github.com/govindaala/hotel_app/actions/runs/45093330929) succeeded on `main`, SHA `c52ed32ce365db9b2b27fc02d92fbad2a61570de`; all build, artifact-upload and release steps succeeded. Artifact `AALA-POS-294` uploaded.
- Historical PR run [#288](https://github.com/govindaala/hotel_app/actions/runs/44285764172) failed at `Build APK`: Maven Central returned HTTP 429 for `com.squareup:javawriter:2.5.0` and `org.ow2.asm:asm:9.1` on both attempts. Later PR runs #292/#293 and Push #294 succeeded; no new failure was observed.
- The workflow's `latest` release asset was updated 2026-11-23 01:17:50 UTC, but the Git tag `latest` still points to commit `f7c76b20d246b17bfd3606b8fb362fe4a6bd433f` from 2026-09-03, 371 commits behind current `main`. This is a release-provenance/rollback traceability concern; the APK asset itself is current from run #294.
- GitHub reports `main.protected = false`; no branch-protection setting was changed. Local Flutter/Dart commands, device tests and production Supabase schema checks were not available.

Confirmed source-level risks remain:

1. **P1 — custom-menu tenant isolation.** Migration `supabase/migrations/20261105100000_custom_menu_and_kot_ready_metrics.sql` lines 15–22 enables RLS but grants `FOR ALL` policies with `USING (true)` and `WITH CHECK (true)` to both `anon` and `authenticated`, and grants CRUD to both. App startup initializes Supabase with the public publishable key and restores role/store/staff/PIN from SharedPreferences; no Supabase Auth sign-in/session calls were found in `lib/main.dart`. Client-side store filters are not an authorization boundary. Impact is conditional on this migration being present in the live schema; production schema was not inspected. A safe correction requires a server-verifiable identity and store-membership model, least-privilege RLS and cross-store tests. Do not replace `true` with another client-supplied store filter.
2. **P1 — settlement retry can create a second sale.** Table settlement generates `BILL-${DateTime.now().millisecondsSinceEpoch}` inside `completeSettlement` (`lib/main.dart` around line 2185); direct counter sale similarly generates `POS-${DateTime.now().millisecondsSinceEpoch}` (`lib/screens/admin/counter_sale_screen.dart` around line 559). The SQL unique key is `(store_code, bill_no)`, so it protects retries only when the same bill number is reused. A timeout after server commit followed by a fresh retry can use a new bill number and create another invoice/CASH_IN ledger row.
3. **P2 — no final-settlement offline replay.** `_syncPendingOfflineOperations` handles `hotel_kots`, `hotel_kots_update` and `counter_inventory_update`, but no settlement/invoice entity. KOT queueing is not offline billing.

No app-code fix was applied: the P1 authorization finding cannot be safely repaired without a real identity/store-membership contract, and changing financial retry identity without a durable local immutable operation record plus backend uniqueness contract risks duplicate or missing sales. Flutter/Dart and an integration-test environment are unavailable. No production schema was checked or changed.

### Next work

1. Restore Node `22.23.4+` (or another package-supported version), obtain the current AALA APK and run REA Flutter static analysis; only then consider the pinned JADX bridge for native code.
2. Obtain a vendor/user-authorized test session or APK before attempting deeper competitor app inspection. Continue TMBill and Petpooja only with reproducible evidence, then move through GoFrugal, Restroworks, Rista and PosBytz.
3. Design Supabase Auth/store membership and least-privilege RLS before enabling custom-menu cloud access; separately design durable, retry-stable checkout IDs and exact-once invoice/ledger/KOT effects before any settlement patch.
4. Fix release provenance only in a reviewed feature branch after confirming the intended moving-tag/release policy; do not alter workflow settings automatically.
