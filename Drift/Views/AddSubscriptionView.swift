//
//  AddSubscriptionView.swift
//  Drift
//
//  The add / edit form (Part 2 §10.2). One screen serves both: pass `existing`
//  to edit, or nothing to add. The user enters a per-cycle price; we normalize
//  it to the stored monthly cost and derive the next renewal date with the
//  BillingCycle helpers. Picking a known service links it (serviceID) and
//  auto-fills the name and category, which also drives the row icon/color.
//
//  Adding a new subscription is gated by the free tier (the backstop for any
//  entry point); editing an existing one is never gated.
//

import SwiftData
import SwiftUI
import WidgetKit

struct AddSubscriptionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(DriftStore.self) private var store

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var allSubscriptions: [Subscription]

    /// The subscription being edited, or `nil` when adding a new one.
    let existing: Subscription?

    @State private var name = ""
    @State private var amountText = ""
    @State private var currencyCode = "USD"
    @State private var cycle: BillingCycle = .monthly
    @State private var customDays = 30
    @State private var startDate = Date()
    @State private var categoryID: PersistentIdentifier?
    @State private var serviceID: String?
    /// Where the user pays for this. `.unknown` = "not sure yet" (the default),
    /// stored as `nil` on the model so the cancel screen asks later. Optional by
    /// design — never required to save.
    @State private var billingChannel: BillingChannel = .unknown

    @State private var guideStore = CancellationGuideStore()
    @State private var isPickingService = false
    @State private var isShowingPaywall = false
    @State private var isShowingCategoryManager = false

    /// Bumped on a successful save so the success haptic fires.
    @State private var saveTick = 0

    /// Tracks which text field owns the keyboard. The number pad has no return
    /// key, so the keyboard toolbar's "Done" button clears this to dismiss it.
    private enum Field { case name, amount }
    @FocusState private var focusedField: Field?

    init(existing: Subscription? = nil) {
        self.existing = existing
    }

    private var isEditing: Bool { existing != nil }

    /// Per-cycle amount the user typed, parsed leniently (accepts "," as ".").
    private var amount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var resolvedCustomDays: Int? {
        cycle == .custom ? customDays : nil
    }

    private var monthlyEquivalent: Decimal {
        cycle.monthlyCost(forCycleAmount: amount, customCycleDays: resolvedCustomDays)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0
    }

    /// Display name of the currently linked service, if any.
    private var linkedServiceName: String? {
        guard let serviceID else { return nil }
        return guideStore.guide(for: serviceID)?.serviceName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    Button {
                        isPickingService = true
                    } label: {
                        HStack {
                            Text("Service")
                            Spacer()
                            Text(linkedServiceName ?? "Custom")
                                .foregroundStyle(DriftTheme.subtleText)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Basics") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                }

                Section("Price") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .amount)

                    Picker("Currency", selection: $currencyCode) {
                        ForEach(ExchangeRates.rates.keys.sorted(), id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }

                    Picker("Billing cycle", selection: $cycle) {
                        ForEach(BillingCycle.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }

                    if cycle == .custom {
                        Stepper("Every \(customDays) days", value: $customDays, in: 1...365)
                    }

                    if amount > 0 {
                        LabeledContent("Monthly equivalent") {
                            Text(monthlyEquivalent, format: .currency(code: currencyCode))
                                .foregroundStyle(DriftTheme.subtleText)
                        }
                    }
                }

                Section("Schedule") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                }

                Section("Category") {
                    Picker("Category", selection: $categoryID) {
                        Text("None").tag(PersistentIdentifier?.none)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.iconSymbol)
                                .tag(Optional(category.persistentModelID))
                        }
                    }
                    Button {
                        isShowingCategoryManager = true
                    } label: {
                        Label("Manage categories", systemImage: "square.grid.2x2")
                    }
                }

                Section {
                    Picker("Where you pay", selection: $billingChannel) {
                        Text("Not sure yet").tag(BillingChannel.unknown)
                        ForEach(BillingChannel.selectableChannels) { channel in
                            Text(channel.displayName).tag(channel)
                        }
                    }
                } header: {
                    Text("Where you pay")
                } footer: {
                    Text("Optional. Apple, Google, Amazon and others each cancel in a different place, so this helps Drift show the right steps later. You can set it anytime.")
                }
            }
            .navigationTitle(isEditing ? "Edit Subscription" : "Add Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTapOutside()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                // The number pad has no return key; this puts the keyboard away.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        focusedField = nil
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Dismiss keyboard")
                }
            }
            .sheet(isPresented: $isPickingService) {
                ServicePickerView { applyService($0) }
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingCategoryManager) {
                NavigationStack {
                    CategoryManagerView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isShowingCategoryManager = false }
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            }
            .driftHaptic(.subscriptionAdded, trigger: saveTick)
            .onAppear(perform: populate)
        }
    }

    /// Applies a service chosen from the picker: links it and auto-fills the
    /// name and best-matching category. "Custom" (nil) only clears the link.
    private func applyService(_ guide: CancellationGuide?) {
        serviceID = guide?.id
        guard let guide else { return }
        name = guide.serviceName
        if let mapped = matchedCategory(for: guide.category) {
            categoryID = mapped.persistentModelID
        }
    }

    /// Maps a guide's category string to a seeded Category by name, falling back
    /// to "Other" when there's no exact match (e.g. the guides' "Family").
    private func matchedCategory(for guideCategory: String) -> Category? {
        if let exact = categories.first(where: {
            $0.name.localizedCaseInsensitiveCompare(guideCategory) == .orderedSame
        }) {
            return exact
        }
        return categories.first {
            $0.name.localizedCaseInsensitiveCompare("Other") == .orderedSame
        }
    }

    /// Pre-fills the form when editing, reversing the stored monthly cost back
    /// into the per-cycle amount the user originally entered.
    private func populate() {
        guard let existing else { return }
        name = existing.name
        currencyCode = existing.currencyCode
        cycle = existing.billingCycle
        customDays = existing.customCycleDays ?? 30
        startDate = existing.startDate
        categoryID = existing.category?.persistentModelID
        serviceID = existing.serviceID
        billingChannel = existing.billingChannel ?? .unknown

        let perCycle = existing.billingCycle.cycleAmount(
            forMonthlyCost: existing.monthlyCost,
            customCycleDays: existing.customCycleDays
        )
        amountText = Self.editableString(from: perCycle)
    }

    /// Adding a new subscription is gated by the free tier; editing never is.
    /// The "+" entry checks this too, so this is the backstop for any other path
    /// (a future Siri / deep-link add must not slip past the limit).
    private func attemptSave() {
        if existing == nil && !store.canAddSubscription(currentCount: allSubscriptions.count) {
            isShowingPaywall = true
        } else {
            save()
        }
    }

    private func save() {
        let monthly = cycle.monthlyCost(forCycleAmount: amount, customCycleDays: resolvedCustomDays)
        let renewal = cycle.nextRenewal(onOrAfter: Date(), seed: startDate, customCycleDays: resolvedCustomDays)
        let category = categories.first { $0.persistentModelID == categoryID }

        let subscription = existing ?? Subscription()
        subscription.name = name.trimmingCharacters(in: .whitespaces)
        subscription.monthlyCost = monthly
        subscription.currencyCode = currencyCode
        subscription.billingCycle = cycle
        subscription.customCycleDays = resolvedCustomDays
        subscription.startDate = startDate
        subscription.nextRenewalDate = renewal
        subscription.category = category
        subscription.serviceID = serviceID
        // Store `nil` for "not sure yet" so the cancel screen knows to ask.
        subscription.billingChannel = billingChannel == .unknown ? nil : billingChannel

        // A subscription's icon and color follow its category, so changing the
        // category (on add or edit) updates the row's look to match. Clearing
        // the category resets it to the neutral "no category" look.
        if let category {
            subscription.iconName = category.iconSymbol
            subscription.customColor = category.colorHex
        } else {
            subscription.iconName = "creditcard.fill"
            subscription.customColor = "#5E5CE6"
        }

        if existing == nil {
            context.insert(subscription)
        }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        saveTick += 1
        dismiss()
    }

    /// Renders a Decimal for the editable amount field without trailing-zero noise.
    private static func editableString(from value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        formatter.usesGroupingSeparator = false
        let number = NSDecimalNumber(decimal: value)
        return formatter.string(from: number) ?? number.stringValue
    }
}
