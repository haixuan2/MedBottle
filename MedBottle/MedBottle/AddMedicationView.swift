import SwiftUI

struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MedicationStore

    @StateObject private var searchManager = MedicationSearchManager()

    @State private var name = ""
    @State private var searchText = ""
    @State private var selectedRXCUI: String?
    /// Once the user edits the name themselves, a late lookup must not overwrite it.
    @State private var hasEditedName = false
    @State private var tabletQuantity = MedicationQuantityInputConfiguration.tabletCount.makeState(value: 30)
    @State private var doseQuantity = MedicationQuantityInputConfiguration.doseCount.makeState(value: 1)
    @State private var colorHex = AppTheme.bottleColors[0]
    @State private var medicationClassification: MedicationClassification = .prescription
    @State private var reminders: [Medication.Reminder] = []
    @State private var isShowingMoreOptions = false
    @State private var addedMedication: Medication?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case search
        case name
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bottle") {
                    medicationSearchField
                    nameField
                    MedicationQuantityInputRow(
                        title: "Tablets",
                        quantity: $tabletQuantity
                    )
                }

                Section {
                    DisclosureGroup("More options", isExpanded: $isShowingMoreOptions) {
                        MedicationQuantityInputRow(
                            title: "Per dose",
                            quantity: $doseQuantity
                        )

                        Picker("Classification", selection: $medicationClassification) {
                            ForEach(MedicationClassification.allCases) { classification in
                                Text(classification.title).tag(classification)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Bottle color")
                            BottleColorPicker(colorHex: $colorHex)
                        }
                    }
                } footer: {
                    Text("Classification is filled in automatically when you pick a search result.")
                }

                if isShowingMoreOptions {
                    MedicationReminderSection(
                        medicationName: reminderMedicationName,
                        dosageAmount: doseQuantity.value ?? MedicationQuantityLimits.doseCount.lowerBound,
                        reminders: $reminders
                    )
                }
            }
            .navigationTitle("New Medication")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addMedication)
                        .disabled(!canAddMedication)
                }
            }
            .sheet(item: $addedMedication) { medication in
                ReminderFollowUpPrompt(medication: medication) {
                    addedMedication = nil
                    dismiss()
                }
                .environmentObject(store)
            }
        }
    }

    // MARK: - Name and search

    /// Search returns a *selection*; it no longer writes straight into `name`.
    private var medicationSearchField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search medication", text: $searchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .search)
                    .onChange(of: searchText) { _, newValue in
                        searchManager.scheduleSearch(for: newValue)
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchManager.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }

            searchResults
        }
        .padding(.vertical, 2)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .name)
                    .onChange(of: name) { _, _ in
                        if focusedField == .name {
                            hasEditedName = true
                        }
                    }

                if searchManager.isResolvingSelection {
                    ProgressView()
                        .accessibilityLabel("Looking up medication details")
                }
            }

            if showsNameRequirement {
                Text("Enter a name for this medication.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if searchManager.isSearching {
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching")
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        } else if !searchManager.results.isEmpty {
            VStack(spacing: 0) {
                ForEach(searchManager.results) { result in
                    Button {
                        select(result)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if result.id != searchManager.results.last?.id {
                        Divider()
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else if let message = searchManager.message {
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    private func select(_ result: MedicationSearchResult) {
        selectedRXCUI = result.rxcui
        hasEditedName = false
        name = result.name
        searchText = ""
        searchManager.clearResults()
        focusedField = nil

        Task {
            let details = await searchManager.details(for: result)
            // Never clobber a field the user has since edited, or a newer selection.
            guard selectedRXCUI == result.rxcui else { return }
            if !hasEditedName {
                name = details.name
            }
            medicationClassification = details.classification
        }
    }

    // MARK: - Validation and add

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddMedication: Bool {
        !trimmedName.isEmpty && tabletQuantity.isValid && doseQuantity.isValid
    }

    /// Surfaced under the offending row rather than left to a greyed-out Add button.
    private var showsNameRequirement: Bool {
        trimmedName.isEmpty && (hasEditedName || !searchText.isEmpty)
    }

    private var reminderMedicationName: String {
        trimmedName.isEmpty ? "Medication" : trimmedName
    }

    private func addMedication() {
        guard canAddMedication else { return }

        let medication = store.addMedication(
            name: name,
            tablets: tabletQuantity.value ?? MedicationQuantityLimits.tabletCount.lowerBound,
            dose: doseQuantity.value ?? MedicationQuantityLimits.doseCount.lowerBound,
            colorHex: colorHex,
            classification: medicationClassification,
            reminders: reminders,
            rxcui: selectedRXCUI
        )

        // Ask about a reminder only when none was set in the form.
        if let medication, reminders.isEmpty {
            addedMedication = medication
        } else {
            dismiss()
        }
    }
}

/// Asked once, right after the bottle is added — the only moment a reminder request
/// has obvious context. Notification permission is requested from here, not at launch.
private struct ReminderFollowUpPrompt: View {
    @EnvironmentObject private var store: MedicationStore

    let medication: Medication
    var onFinish: () -> Void

    @State private var reminders: [Medication.Reminder] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set a reminder for \(medication.name)?")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("A reminder is what turns the bottle count into an answer about today.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }

                MedicationReminderSection(
                    medicationName: medication.name,
                    dosageAmount: medication.tabletsPerDose,
                    reminders: $reminders
                )
            }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now", action: onFinish)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set reminder") {
                        save()
                        onFinish()
                    }
                    .disabled(reminders.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard var updated = store.medications.first(where: { $0.id == medication.id }) else { return }
        updated.reminders = reminders
        store.updateMedication(updated)
    }
}

struct MedicationQuantityInputRow: View {
    let title: String

    @Binding private var quantity: MedicationQuantityInputState
    @FocusState private var isFocused: Bool

    init(
        title: String,
        quantity: Binding<MedicationQuantityInputState>
    ) {
        self.title = title
        self._quantity = quantity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(quantitySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button {
                        decrement()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!quantity.canDecrement)
                    .accessibilityLabel("Decrease \(title.lowercased())")
                    .accessibilityValue(quantitySummary)

                    TextField(title, text: quantityText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 76)
                        .focused($isFocused)
                        .accessibilityLabel("\(title) quantity")
                        .accessibilityValue(quantity.accessibilityValue)
                        .accessibilityHint("Enter a quantity, or use the increment and decrement buttons.")
                        .onChange(of: isFocused) { _, focused in
                            if !focused && quantity.isValid {
                                quantity = quantity.configuration.makeState(value: quantity.value ?? quantity.configuration.range.lowerBound)
                            }
                        }

                    Button {
                        increment()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!quantity.canIncrement)
                    .accessibilityLabel("Increase \(title.lowercased())")
                    .accessibilityValue(quantitySummary)
                }
            }

            if let errorMessage = quantity.validationError?.localizedDescription {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(title) error: \(errorMessage)")
            }
        }
        .toolbar {
            // The number pad has no return key; without this the field cannot be dismissed.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFocused = false }
                    .disabled(!isFocused)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                increment()
            case .decrement:
                decrement()
            @unknown default:
                break
            }
        }
    }

    private var quantitySummary: String {
        quantity.accessibilityValue
    }

    private var quantityText: Binding<String> {
        Binding(
            get: { quantity.text },
            set: { quantity = quantity.configuration.makeState(text: $0) }
        )
    }

    private func increment() {
        quantity = quantity.configuration.incrementedState(from: quantity)
    }

    private func decrement() {
        quantity = quantity.configuration.decrementedState(from: quantity)
    }
}
