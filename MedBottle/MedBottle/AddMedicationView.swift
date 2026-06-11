import SwiftUI

struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MedicationStore

    @StateObject private var searchManager = MedicationSearchManager()

    @State private var name = ""
    @State private var searchText = ""
    @State private var selectedRXCUI: String?
    @State private var tabletQuantity = MedicationQuantityInputConfiguration.tabletCount.makeState(value: 30)
    @State private var doseQuantity = MedicationQuantityInputConfiguration.doseCount.makeState(value: 1)
    @State private var colorHex = "D99A00"
    @State private var customColor = Color(hex: "D99A00")
    @State private var medicationShape: MedicationShape = .tablet
    @State private var medicationClassification: MedicationClassification = .prescription
    @State private var reminders: [Medication.Reminder] = []

    private let colors = ["D99A00", "C87B00", "8FB7D8", "74A88D", "D35F7B"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Bottle") {
                    medicationSearchField
                    MedicationQuantityInputRow(
                        title: "Tablets",
                        quantity: $tabletQuantity
                    )
                    MedicationQuantityInputRow(
                        title: "Per dose",
                        quantity: $doseQuantity
                    )
                }

                Section("Medication Shape") {
                    Picker("Shape", selection: $medicationShape) {
                        ForEach(MedicationShape.allCases) { shape in
                            Text(shape.title).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Classification") {
                    Picker("Classification", selection: $medicationClassification) {
                        ForEach(MedicationClassification.allCases) { classification in
                            Text(classification.title).tag(classification)
                        }
                    }
                    .pickerStyle(.segmented)

                    if searchManager.isResolvingSelection {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Checking classification")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                MedicationReminderSection(
                    medicationName: reminderMedicationName,
                    dosageAmount: doseQuantity.value ?? MedicationQuantityLimits.doseCount.lowerBound,
                    reminders: $reminders
                )

                Section("Color") {
                    ColorPicker("Bottle color", selection: $customColor, supportsOpacity: false)
                        .onChange(of: customColor) { _, newColor in
                            colorHex = newColor.hexString
                        }

                    HStack(spacing: 16) {
                        ForEach(colors, id: \.self) { color in
                            Button {
                                colorHex = color
                                customColor = Color(hex: color)
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if colorHex == color {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("New Medication")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addMedication(
                            name: name,
                            tablets: tabletQuantity.value ?? MedicationQuantityLimits.tabletCount.lowerBound,
                            dose: doseQuantity.value ?? MedicationQuantityLimits.doseCount.lowerBound,
                            colorHex: colorHex,
                            shape: medicationShape,
                            classification: medicationClassification,
                            reminders: reminders
                        )
                        dismiss()
                    }
                    .disabled(!canAddMedication)
                }
            }
        }
    }

    private var canAddMedication: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        tabletQuantity.isValid &&
        doseQuantity.isValid
    }

    private var reminderMedicationName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Medication" : trimmedName
    }

    private var medicationSearchField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search medication", text: $searchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        let trimmedText = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

                        if selectedRXCUI != nil && trimmedText == name {
                            return
                        }

                        selectedRXCUI = nil
                        name = newValue
                        searchManager.scheduleSearch(for: newValue)
                    }
            }

            searchResults
        }
        .padding(.vertical, 2)
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
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(result.shape.title)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
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
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    private func select(_ result: MedicationSearchResult) {
        selectedRXCUI = result.rxcui
        name = result.name
        searchText = result.name
        medicationShape = result.shape
        searchManager.clearResults()

        Task {
            let details = await searchManager.details(for: result)
            guard selectedRXCUI == result.rxcui else { return }
            name = details.name
            searchText = details.name
            medicationShape = details.shape
            medicationClassification = details.classification
        }
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
                        .frame(width: 76)
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
