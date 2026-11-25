# REA-driven restaurant POS reverse-engineering tracker

**Last updated:** 2026-11-25 15:46 IST  
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


## 9. Daily delta — 2026-11-24

### AALA workflow verification

- Current `main` remains `c52ed32ce365db9b2b27fc02d92fbad2a61570de`; the five commits since the previous app-source baseline affected only this documentation tracker. No local checkout is mounted, so local working-tree cleanliness is not asserted.
- Latest Push run [#294](https://github.com/govindaala/hotel_app/actions/runs/45093330929) remains successful on `main`, SHA `c52ed32ce365db9b2b27fc02d92fbad2a61570de`. Build and artifact upload succeeded; the direct-release step succeeded. Artifact `AALA-POS-294` is present and retained through 2026-12-07.
- Previous PR run [#295](https://github.com/govindaala/hotel_app/actions/runs/45156554281) has now completed successfully on `research/rea-pos-coverage-2026-11-23`, SHA `208674d374240e21598858cbf35c28a1b64eb472`. The build and artifact upload succeeded; artifact `AALA-POS-295` is present through 2026-12-07; the release step was skipped as expected for a pull request.
- No new failed, cancelled or in-progress run was present in the latest relevant run list. Historical Maven Central HTTP 429 failure #288 remains resolved by later successful runs; no rerun was requested or issued.
- The moving release asset `app-release.apk` was last uploaded by #294 (SHA-256 `b903ffc3b1228b8e28fe1dcbd51d7bae4c024ddd4c7c79f700676f274c8d4cc1`). The Git tag `latest` still resolves to old commit `f7c76b20d246b17bfd3606b8fb362fe4a6bd433f`, not the current `main` commit. This remains a release-provenance/rollback traceability risk; no tag or workflow changes were made.
- The existing open PR [#34](https://github.com/govindaala/hotel_app/pull/34) is the only open PR returned for AALA. This tracker update is being added to the same branch; no new PR is required.

### REA project state and execution boundary

- Canonical repository reconfirmed: [morluto/rea](https://github.com/morluto/rea), owner `morluto`, repository `rea`, README title **REA: Reverse Engineer Anything**, MIT license. Current source `main` HEAD observed 2026-11-24: `1e1db9e342ad13d26c27f34af8a2d7a5648387c9`.
- Latest published release remains [`rea-agents 6.10.1`](https://github.com/morluto/rea/releases/tag/rea-agents-6.10.1), published 2026-11-20. Package metadata requires Node `^22.23.4 || ^24.22.1 || >=26.12.1`; available Node is `v22.16.0`, npm `10.9.2`, Java `21.0.12`.
- Today's source/docs review covered the README, package metadata, installation, CLI/Evidence, Android/JADX, Flutter AOT, Apktool resources, SECURITY, DISCLAIMER and MIT license. The latest recent source commits are mostly CI/test/tooling changes and are newer than the published 6.10.1 release.
- REA [PR #13361](https://github.com/morluto/rea/pull/13361), previously tracked as open, is now merged. It includes Android JADX indexing/caching and regression-test changes, but those newer source changes must not be treated as included in the unchanged published 6.10.1 npm package without a later release.
- New open REA feature request [#14038](https://github.com/morluto/rea/issues/14038), filed 2026-11-23, describes compiled Android binary XML (`AndroidManifest.xml`) and `resources.arsc` as opaque to generic artifact inspection; a caller-supplied Apktool path remains the separate resource-decoding option. This is an open proposal/limitation, not an implemented capability.
- CLI execution remains blocked: `rea`, `adb`, `emulator`, `apktool`, `jadx`, `flutter` and `dart` are not installed; no AALA APK/AAB is mounted; no authorized competitor test account/device is available. Flutter APK parsing can identify build/snapshot/library facts but does not recover full Dart source. JADX requires a supplied pinned headless bridge; runtime/browser/device operations require an authorized target and explicit review.
- **No REA command ran and no target app was reverse-engineered today.** Repository/documentation inspection is recorded separately from app inspection.

### Competitor evidence delta — public vendor documentation only

All observations below were accessed 2026-11-24 through public official vendor pages/help articles. They are vendor-authored workflow descriptions, not REA inspection, interactive demo execution or independent verification.

| Target | Source URL | Access and documented observation | Evidence strength | AALA use |
|---|---|---|---|---|
| GoFrugal Touch POS | [Login and punching a KOT](https://community.gofrugal.com/portal/en/kb/gofrugalserveeasy/touch-pos/articles/login-and-punching-a-kot) | Public vendor help article with screen/image references; describes dine-in/table selection, table states, steward assignment, category/item selection, quantity/priority and KOT submission. | Vendor documentation; public screen references, no live demo execution. | Use table state transitions and a reproducible table→steward→KOT acceptance test; do not copy vendor UI. |
| GoFrugal KDS | [KDS — Kitchen Display Screen](https://community.gofrugal.com/portal/en/kb/servquick/general/articles/kds-kitchen-display-screen) | Public vendor help article describes role/permission setup and item-level Pending/Preparing/Dispatched/Completed/Ready/Served progress, with aggregate item counts. | Vendor documentation; not independently verified. | Compare AALA's current KOT-level status with item-level preparation and role-gated state transitions; add tests before adopting a richer model. |
| GoFrugal table management | [Table screen in brief](https://community.gofrugal.com/portal/en/kb/gofrugalserveeasy/general/table-management/customer-management/articles/table-screen-in-brief) | Public help article describes available/occupied/summary filters, additional KOT, bill conversion and steward summary. | Vendor documentation; not independently verified. | Add explicit table-state and running-order test cases, including additional KOT and bill conversion. |
| PosBytz KOT | [Kitchen Order Ticket System](https://posbytz.com/en/restaurant/features/kitchen-order-ticket-system/) | Public vendor feature page describes multi-channel KOT intake, category/station routing, modifiers/notes, cancellation/change notifications, split/partial KOT, preparation state and offline printing/sync. | Vendor claim; no public interactive flow executed. | Test category routing, partial fulfilment, cancellation, offline print and duplicate-safe reconnect. |
| PosBytz KDS | [Kitchen Display System](https://posbytz.com/en/restaurant/features/kitchen-display-system/) | Public vendor feature page describes kitchen-wise display routing, priority alerts, live statuses and preparation-time analytics. | Vendor claim; unverified. | Build acceptance scenarios for station routing and per-item timing only after AALA's data model is inspected. |
| PosBytz QR ordering | [QR Code Ordering](https://posbytz.com/en/restaurant/features/qr-code-ordering/) | Public vendor feature page describes table-specific QR, browser menu, order submission to POS/KOT and additional rounds on a table. | Vendor claim; no interactive guest checkout completed. | AALA's QR generator currently encodes store/table into a menu URL and creates printable standees; verify web-menu→POS order ingestion before claiming end-to-end QR ordering parity. |
| Petpooja offline POS | [Offline POS](https://www.petpooja.com/offline-pos) | Official public product page describes local bills/orders/KOT during internet loss and later cloud sync of menu/price/online order data. | Vendor claim; architecture not independently tested. | Prioritize durable local settlement records, idempotent replay, visible pending/synced state and conflict recovery; do not assume Petpooja's claimed behavior is proven. |

Coverage remains: shortlist 15/15; vendor-page survey 15/15; public demo page inspected 1/15 (TMBill page only, no interactive flow completed); REA static APK inspections 0/15; REA runtime/device inspections 0/15; independently verified competitor feature claims 0. The seven documentation pages above expand workflow questions, not demo or reverse-engineering counts.

### AALA source audit — unchanged critical risks

- **P1 tenant isolation:** migration `20261105100000_custom_menu_and_kot_ready_metrics.sql` still defines permissive `FOR ALL` RLS policies with `USING (true)` / `WITH CHECK (true)` for both `anon` and `authenticated`. App startup uses a public publishable key, and repository search found no Supabase Auth sign-in call. Production migration status was not inspected; exposure is conditional on this migration being applied. A safe correction requires authenticated server-verifiable store membership, least-privilege RLS and cross-store tests.
- **P1 settlement retry:** `settle_hotel_order` has a unique `(store_code, bill_no)` index and returns the existing invoice for the *same* bill number. Both table settlement and counter sale currently generate a fresh millisecond-based bill number per attempt. An ambiguous timeout followed by a new attempt can therefore bypass the existing deduplication key and create a second invoice/ledger effect.
- **P2 offline invoice:** the durable SQLite queue stores IDs/store/entity/payload/attempts, but the dispatcher currently replays KOT create/update and counter inventory only; there is no final invoice/settlement replay handler.
- **P2 release provenance:** moving `latest` APK asset and immutable old Git tag do not identify the same source commit.
- Visible Dart test files cover LAN authorization, line JSON protocol, offline database, report request validation and WhatsApp bill-share service. The APK workflow itself runs dependency setup and release build but does not run `flutter analyze` or `flutter test`. No Flutter/Dart executable or Android device/emulator is available in this environment; tests were not run.
- QR source review: `lib/screens/admin/qr_table_generator_screen.dart` generates a URL of the form `https://govindaala.github.io/hotel_menu/?store=<storeCode>&table=<tableNo>` and can create a PDF standee. The target web menu's actual order-to-KOT/POS behavior was not tested, so end-to-end QR ordering remains unverified.

No app source change was made. The tenant fix cannot be safely designed without a server-verifiable identity/store-membership contract; the settlement fix needs a durable immutable operation record and an exact-once server idempotency contract. A client-only timestamp change would not repair the failure mode. Do not apply production migrations or advertise offline final billing until these contracts and regression tests exist.

### Next actions

1. Make a supported Node runtime (22.23.4+) available, install/use REA locally, and analyze the actual AALA release APK with the Flutter pure-parser family; retain APK SHA-256 and REA Evidence.
2. Obtain a vendor/public demo or authorized test session and record reproducible Petpooja/GoFrugal/PosBytz workflows; keep claims and observations separate.
3. Design Supabase Auth/store membership and least-privilege RLS, then add cross-store tests before enabling custom-menu cloud writes.
4. Design durable checkout operation IDs, immutable invoice payloads, exact-once ledger effects and crash/retry tests before implementing offline settlement.
5. Resolve the moving release-tag policy only through a reviewed feature-branch change; do not modify workflow configuration automatically.

No application code, production data/schema, workflow, secrets, settings, branch protection or paid resource was changed by this documentation update.


## 10. Daily delta — 2026-11-25

### AALA repository and APK workflow

- Current `main`: `d40bb50c48f48ca27982350e743b5f5006b859bf` (2026-11-24 18:06:38 UTC). Since the prior recorded baseline `cef7af4eb61a33b706fc07f5e788918d2ffac641`, four commits added the evidence matrix and Replica-skill Flutter workflow notes and extended offline ID tests; **no application-runtime source changed**. PR [#35](https://github.com/govindaala/hotel_app/pull/35) merged at that commit. No open AALA PR was returned. No local checkout is mounted, so local working-tree cleanliness is not asserted.
- Latest APK Push run [#300](https://github.com/govindaala/hotel_app/actions/runs/45455926215): `main`, SHA `d40bb50c48f48ca27982350e743b5f5006b859bf`, completed/success. Build APK, artifact upload and direct APK release steps all succeeded. Artifact `AALA-POS-300` (26,328,790 bytes) is retained through 2026-12-08 18:11 UTC.
- Latest APK PR run [#299](https://github.com/govindaala/hotel_app/actions/runs/45454915646): `feat/replica-skill-aala-workflow-2026-11-24`, SHA `d04aef5a2c81c048e8224df8b2e246324bc72a8c`, completed/success. Build and artifact upload passed; release was skipped as expected for a PR. Artifact `AALA-POS-299` was uploaded.
- Immediately previous PR run [#298](https://github.com/govindaala/hotel_app/actions/runs/45454766408) was cancelled during the `Build APK` step, with upload/release skipped. The newer #299 run completed successfully; the workflow uses `cancel-in-progress: true`, so this is consistent with superseding an earlier branch commit rather than a current build failure. No failed or in-progress run is present in the latest target-workflow checks.
- The latest release asset `app-release.apk` was updated from #300 on 2026-11-24 18:11 UTC (asset SHA-256 `7b1cae54bccff2b8a5ffeea3b81fa478be937d0654aab4ae68e235d8e6f90fea`): [download APK](https://github.com/govindaala/hotel_app/releases/download/latest/app-release.apk). **Release-provenance warning:** Git tag `latest` still points to `f7c76b20d246b17bfd3606b8fb362fe4a6bd433f`, which is 378 commits behind current `main`, while the moving release asset is from #300. The binary asset is current, but the tag does not identify its source commit. No tag or release configuration was changed.
- The configured APK workflow still does not run `flutter analyze` or `flutter test`; a successful APK build proves packaging/build only, not POS behavior.

### REA canonical project and execution readiness

- Canonical identity confirmed again: [morluto/rea](https://github.com/morluto/rea), owner `morluto`, README title **REA: Reverse Engineer Anything**, public repository, MIT license. The official README links to [rea.tools](https://rea.tools/) and the `rea-agents` package.
- Source `main` latest commit observed today: [`2e1cc32586c60ae59c0bea66ddd091be7f49df9b`](https://github.com/morluto/rea/commit/2e1cc32586c60ae59c0bea66ddd091be7f49df9b), 2026-11-25 10:16 UTC. Latest published release remains [`rea-agents 6.10.1`](https://github.com/morluto/rea/releases/tag/rea-agents-6.10.1), published 2026-11-20; current package metadata declares MIT and Node `^22.23.4 || ^24.22.1 || >=26.12.1`.
- Read today: README, `package.json`, supported-target requirements, installation/setup, CLI/Evidence, Android/JADX analysis, Flutter APK parsing, SECURITY and DISCLAIMER. Supported workflows include Flutter APK structural/build identification, Android package/class analysis through a separately supplied pinned JADX engine, Apktool resource inspection and ADB device/runtime inspection. REA is a local tool, not a sandbox; runtime/device actions require separate authorization and review.
- Execution environment today: Node `v22.16.0` and npm `10.9.2`; Node is below the package's minimum `22.23.4`. OpenJDK 21 is present, but `rea`, `adb`, `emulator`, `flutter`, `dart`, `jadx` and `apktool` are absent. No AALA APK is mounted and no authorized competitor APK/account/device session is available.
- **No REA command was executed and no app was reverse-engineered today.** This is repository/documentation research only. The Flutter parser would give snapshot hash, ABI library digests and engine build facts; it does not recover complete Dart source. Android class inspection needs the pinned JADX bridge and supported runtime. Runtime comparison requires an authorized device/session.

### POS competitor evidence — 2026-11-25

All three sources below were publicly accessed. None is a private app/API inspection.

| Target | Source / access / date | Evidence strength and bounded observation | AALA usefulness / limitation |
|---|---|---|---|
| Petpooja POS Local | [Official POS Local article](https://blog.petpooja.com/industry-business-guides/petpooja-pos-local-that-keeps-data-in-house/), published and updated 2026-07-06; public webpage read 2026-11-25 | Vendor claim. Describes a Bridge Server/local database, LAN-connected billing terminals, bills/KOT/day-end reports held locally, cloud-fed menu/price/aggregator-order sync, scheduled local backups, and up to five days offline for a split server/terminal setup. It explicitly states offline inventory tracking exists but automatic stock consumption on sale is not included. | Useful reference for local-authoritative LAN topology and backup/recovery questions. The vendor's duration and behavior are not independently tested. The explicit inventory limitation reinforces that AALA should not promise recipe/stock parity until its own stock mutations are atomic and reconciled. |
| TMBill | [Public POS demo](https://www.tmbill.com/resources/free-pos-demo/), browser page inspected 2026-11-25 | Public demo page observed: Master POS, OrderFlow Captain and KDS are presented as a connected demonstration; the described path is table/phone order → save KOT → KDS → Served. The page labels itself a simplified browser demo using sample menu/prices and says nothing is sent anywhere. No interactive controls were exercised. | Useful to define an AALA acceptance flow for Captain/ waiter → POS → KOT → KDS → Served. This is not proof of live backend, payment or offline behavior. |
| Restroworks | [Official restaurant POS page](https://www.restroworks.com/restaurant-pos-system/), public webpage read 2026-11-25 | Vendor claim. The page describes counter/table/omnichannel order intake, kitchen station routing, connectivity-loss operation, and recipe/ingredient-level inventory and wastage controls. | Useful for future station-routing and BOM acceptance criteria. No app/demo workflow was executed; vendor-reported performance figures are not independently verified. |

Coverage is unchanged: shortlist 15/15; public vendor-page survey 15/15 (claims only); public demo pages inspected 1/15 (TMBill initial browser view only); REA static APK inspection 0/15; REA runtime/device inspection 0/15; independently verified competitor feature claims 0.

### AALA source audit — new and continuing risks

1. **P1 — concurrent counter stock update can lose a deduction (new source-level finding).** In `lib/screens/admin/counter_sale_screen.dart`, checkout refreshes a stock snapshot and validates quantity, then after settlement writes an absolute client-computed `stock_qty = snapshot - quantity` (around lines 437–613). Two terminals can read the same stock before either write; the later absolute update can overwrite the other terminal's deduction. For example, two 6-unit sales starting from 10 can leave stock at 4 although 12 units were sold. No concurrency test or live two-terminal reproduction was available. The safe correction belongs in a server-side atomic compare-and-decrement/settlement transaction with rollback on insufficient stock, not a client-only arithmetic change.
2. **P1 — ambiguous settlement retry can create duplicate invoice and CASH_IN effects (unchanged).** Table settlement generates a new `BILL-<milliseconds>` inside each submission attempt (`lib/main.dart`, around line 2185); direct counter billing generates a new `POS-<milliseconds>` in `counter_sale_screen.dart` around line 559. The database unique index protects reuse of the same bill number, but a retry after a committed request whose response was lost receives a different number and can create a second sale.
3. **P1 — custom-menu tenant isolation (conditional on migration deployment).** `supabase/migrations/20261105100000_custom_menu_and_kot_ready_metrics.sql` lines 15–22 gives both `anon` and `authenticated` `FOR ALL` policies with `USING (true)` / `WITH CHECK (true)` and CRUD grants. If this migration is present in the live schema, the policy is not store-isolated. Production schema was not inspected; exposure is not asserted as live. The inspected client initializes Supabase with the public anon key and uses a separate LAN challenge flow; repository search found no Supabase Auth sign-in establishing server-verifiable store membership. A client-supplied store filter is not a safe RLS repair.
4. **P2 — final invoice/payment is not in the offline replay dispatcher.** `lib/main.dart` around lines 923–969 replays KOT create/update and counter-inventory updates, not a final settlement entity. Direct counter settlement calls the RPC and does not persist a durable immutable settlement operation before sending.
5. The settlement SQL's same-bill idempotency and customer-name/phone persistence are present in the checked migrations. No current omission of those customer columns is reported. No production schema or transaction was executed.

No application-code fix was made today. The P1 stock race needs a transaction contract and isolated database concurrency tests; the settlement retry needs durable client operation identity plus server-side exactly-once invoice/ledger effects; the RLS issue needs verified Supabase identity/store-membership design. A superficial client patch would risk worsening stock or financial consistency.

### Commands and verification boundary

- Source/API/docs inspections only; no repository checkout is mounted, so no local working-tree command ran.
- `flutter analyze`, `flutter test`, a new APK build, Android installation/device checks, printer checks and live Supabase integration tests were **not run**: Flutter/Dart, emulator/device, local APK and an isolated test database are unavailable. The GitHub workflow runs above are the actual hosted APK build evidence; its YAML has no Dart analyzer/test steps.
- No failed latest Push/PR APK build is present. Run #298 was cancelled and superseded by successful #299. No rerun or dispatch was issued.

### Next engineering priorities

1. Design an atomic stock compare-and-decrement integrated into the final sale transaction, with two-terminal race tests and insufficient-stock rollback.
2. Design durable, immutable, retry-stable settlement identity for both table/parcel and direct-counter paths; add exact-once invoice/items/KOT/ledger integration tests and local restart recovery.
3. Establish Supabase Auth plus server-verifiable store membership and least-privilege RLS before changing the permissive custom-menu policy.
4. Make Node 22.23.4+ and a real AALA APK available; then run REA Flutter static parsing and save artifact SHA-256/Evidence. Use JADX only when the pinned engine and JDK/runtime are ready.
5. Continue the 15-platform tracker with a vendor-authorized or fully public TMBill/Petpooja demonstration; do not raise demo/REA coverage counts until an actual reproducible workflow is captured.

No app code, production data/schema, workflow YAML/settings, secrets, permissions, branch protections, release tag or paid resource was changed in this audit.
