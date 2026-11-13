# POS regression checklist for the consolidated PR

Run these checks on a test restaurant/store before merging or distributing the APK.

## Counter billing
- [ ] Add multiple items and change quantities; totals match item price × quantity.
- [ ] Cash and UPI confirmation each produce exactly one invoice and one set of invoice items.
- [ ] Rapid double-tap on Confirm does not create duplicate bills.
- [ ] Failed settlement keeps the cart available and shows an actionable error.
- [ ] Existing stock is refreshed before checkout; stock cache updates after successful order/bill.

## Customer and receipt
- [ ] Enter a new customer's name/mobile; both are saved on the invoice.
- [ ] Enter a previously used mobile number (10 digits and +91 format); the latest saved name fills in.
- [ ] Share action opens the Android share sheet with the generated PDF attached.
- [ ] Choose WhatsApp, select the intended recipient, and manually press Send; the app must not send without user confirmation.
- [ ] Printer output includes the customer fields when supplied.

## Menu sync and offline mode
- [ ] Add/rename/reprice/toggle availability for a UUID master-menu item; changes survive app restart and appear on another device for the same store.
- [ ] Add a local/custom menu item; it survives app restart and appears on another device for the same store.
- [ ] Rename/reprice/toggle availability on a custom item; the same store sees the updated row after sync.
- [ ] Different store codes do not show one another's menu rows in normal app flows.
- [ ] With internet disabled, the saved local menu remains usable; restore internet and verify sync clears the pending flag.

## LAN client authentication
- [ ] A new TCP client cannot fetch the menu or send KOT/status commands before authenticating.
- [ ] Waiter/cook login uses a one-use challenge response; the raw PIN is not sent over the LAN.
- [ ] A waiter cannot mark a KOT ready or submit another waiter's identity; a cook cannot create a waiter KOT.
- [ ] A saved waiter/cook session reconnects after app restart using the existing locally cached credential.

## KOT and kitchen
- [ ] Counter table order appears in kitchen and remains after app refresh/restart.
- [ ] Mark a KOT Ready; server status, ready timestamp and preparation duration are stored.
- [ ] Undo Ready returns status to pending and clears ready metadata.
- [ ] Offline Ready/Undo changes remain queued and sync when connectivity returns.
- [ ] Settlement closes the relevant table KOTs; daily sales report matches settled invoices.

## Release gate
- [ ] GitHub Actions Android APK build succeeds on this PR head.
- [ ] Test on a physical Android device with the target thermal printer and WhatsApp installed.
- [ ] Do not merge until any failing checks above are fixed.
