# Drift

Calm subscription tracker for iPhone. Local-first, no bank link, no tracking, pay once.

Second app from defrust. Swift 6 / SwiftUI / SwiftData + CloudKit.

- Min iOS: **17.0** (Foundation Models features gate on iOS 26+)
- Bundle ID: `com.defrust.drift`
- Specs live in the project knowledge docs — `drift-quickstart.md` is the entry point
- Tests first, features second: `⌘U` locally; CI runs the `DriftUnit` test plan on every push

## Day 1 scaffold

SwiftLint config, GitHub Actions CI, privacy manifest, and the first 6 Swift Testing
tests (`ExchangeRates`, `BillingCycle`). See `SETUP.md` for the one-time setup steps.
