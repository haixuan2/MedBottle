import SwiftUI

struct ManageMedicationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MedicationStore

    @Binding var selectedMedicationID: Medication.ID?
    @State private var pendingDeletion: Medication?

    var body: some View {
        NavigationStack {
            List {
                if store.medications.isEmpty {
                    ContentUnavailableView(
                        "No medications",
                        systemImage: "pills",
                        description: Text("Added medications will appear here.")
                    )
                } else {
                    Section {
                        // One row, one destination. Reminders are edited inside the editor.
                        ForEach(store.medications) { medication in
                            NavigationLink {
                                MedicationEditorView(medication: medication)
                                    .environmentObject(store)
                            } label: {
                                MedicationManagementRow(medication: medication)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDeletion = medication
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this medication?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented { pendingDeletion = nil }
                    }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { medication in
                Button("Delete \(medication.name)", role: .destructive) {
                    delete(medication)
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { _ in
                Text("Dose history for this medication will be kept.")
            }
        }
    }

    private func delete(_ medication: Medication) {
        guard let index = store.medications.firstIndex(where: { $0.id == medication.id }) else {
            pendingDeletion = nil
            return
        }

        selectedMedicationID = store.deleteMedications(
            at: IndexSet(integer: index),
            selectedID: selectedMedicationID
        )
        pendingDeletion = nil
    }
}

private struct MedicationManagementRow: View {
    let medication: Medication
    private let primaryColor = AppTheme.accent

    private var stockStatus: MedicationStockStatus {
        MedicationDetailSnapshotBuilder().makeStockStatus(for: medication)
    }

    var body: some View {
        HStack(spacing: 12) {
            MedicationBottleGauge(medication: medication, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(medication.classification.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(stockStatus.supplyHeadline)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(stockStatus.level == .ready ? primaryColor : AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            reminderLabel
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// A label, not a second destination — reminders are edited inside the editor.
    private var reminderLabel: some View {
        let nextDate = medication.nextScheduledReminderDate

        return Label {
            Text(nextDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "No reminder")
        } icon: {
            Image(systemName: nextDate == nil ? "bell.slash" : "bell.fill")
        }
        .font(.footnote)
        .foregroundStyle(AppTheme.secondaryText)
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(
            nextDate.map { "Next reminder at \($0.formatted(date: .omitted, time: .shortened))" } ?? "No reminder"
        )
    }
}

private struct MedicationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MedicationStore

    let medication: Medication

    @State private var name: String
    @State private var tabletCount: Int
    @State private var doseCount: Int
    @State private var colorHex: String
    @State private var medicationClassification: MedicationClassification
    @State private var reminders: [Medication.Reminder]

    private let primaryColor = AppTheme.accent

    init(medication: Medication) {
        self.medication = medication
        _name = State(initialValue: medication.name)
        _tabletCount = State(initialValue: medication.tabletsRemaining)
        _doseCount = State(initialValue: medication.tabletsPerDose)
        _colorHex = State(initialValue: medication.bottleColorHex)
        _medicationClassification = State(initialValue: medication.classification)
        _reminders = State(initialValue: medication.reminders)
    }

    var body: some View {
        Form {
            Section("Bottle") {
                TextField("Medication name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Stepper("Tablets: \(tabletCount)", value: $tabletCount, in: 0...500)
                Stepper("Per dose: \(doseCount)", value: $doseCount, in: 1...12)
            }

            Section("Classification") {
                Picker("Classification", selection: $medicationClassification) {
                    ForEach(MedicationClassification.allCases) { classification in
                        Text(classification.title).tag(classification)
                    }
                }
                .pickerStyle(.segmented)
            }

            MedicationReminderSection(
                medicationName: reminderMedicationName,
                dosageAmount: doseCount,
                reminders: $reminders
            )

            Section("Color") {
                BottleColorPicker(colorHex: $colorHex)
            }
        }
        .navigationTitle("Edit Medication")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        store.updateMedication(
            Medication(
                id: medication.id,
                name: name,
                tabletsRemaining: tabletCount,
                tabletsPerDose: doseCount,
                bottleColorHex: colorHex,
                classification: medicationClassification,
                reminders: reminders,
                lastTakenAt: medication.lastTakenAt,
                bottleCapacity: medication.bottleCapacity,
                rxcui: medication.rxcui
            )
        )
    }

    private var reminderMedicationName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Medication" : trimmedName
    }
}

/// The five curated bottle colours as one-tap presets, plus a full colour picker for
/// anything else. Shared by Add and Edit.
struct BottleColorPicker: View {
    @Binding var colorHex: String

    /// A colour the presets do not cover is shown in its own well, so a custom bottle
    /// still reads as the current selection rather than as "none of these".
    private var isCustomColor: Bool {
        !AppTheme.bottleColors.contains(colorHex.uppercased())
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(hex: colorHex) },
            set: { colorHex = $0.hexString }
        )
    }

    var body: some View {
        HStack(spacing: 16) {
            ForEach(AppTheme.bottleColors, id: \.self) { color in
                Button {
                    colorHex = color
                } label: {
                    swatch(Color(hex: color), isSelected: colorHex.uppercased() == color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bottle color \(color)")
                .accessibilityAddTraits(colorHex.uppercased() == color ? [.isButton, .isSelected] : .isButton)
            }

            Spacer(minLength: 0)

            ColorPicker(selection: customColor, supportsOpacity: false) {
                EmptyView()
            }
            .labelsHidden()
            .frame(width: 34, height: 34)
            .overlay {
                if isCustomColor {
                    Circle()
                        .strokeBorder(AppTheme.accent, lineWidth: 2)
                        .frame(width: 40, height: 40)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Custom bottle color")
            .accessibilityValue(colorHex)
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ color: Color, isSelected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }
}

struct MedicationReminderSection: View {
    let medicationName: String
    let dosageAmount: Int
    @Binding var reminders: [Medication.Reminder]

    private let primaryColor = AppTheme.accent

    var body: some View {
        Section("Reminders") {
            if reminders.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("No reminders set", systemImage: "bell.slash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    addReminderLink(isProminent: true)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(reminders) { reminder in
                    NavigationLink {
                        ReminderSetupView(medicationName: medicationName, reminder: reminder) { updatedReminder in
                            upsert(updatedReminder)
                        }
                    } label: {
                        ReminderSummaryRow(reminder: reminder)
                    }
                }
                .onDelete { offsets in
                    reminders.remove(atOffsets: offsets)
                }

                addReminderLink(isProminent: false)
            }
        }
    }

    private func addReminderLink(isProminent: Bool) -> some View {
        NavigationLink {
            ReminderSetupView(
                medicationName: medicationName,
                reminder: Medication.Reminder(dosageAmount: dosageAmount)
            ) { reminder in
                upsert(reminder)
            }
        } label: {
            if isProminent {
                HStack {
                    Label("Add Reminder", systemImage: "bell.badge.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 11)
                .padding(.horizontal, 12)
                .background(primaryColor, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Label("Add Reminder", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryColor)
            }
        }
        .buttonStyle(.plain)
    }

    private func upsert(_ reminder: Medication.Reminder) {
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index] = reminder
        } else {
            reminders.append(reminder)
        }
    }
}

private struct ReminderSummaryRow: View {
    let reminder: Medication.Reminder
    private let primaryColor = AppTheme.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.isActive ? "bell.fill" : "bell.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(reminder.isActive ? primaryColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.time.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold))

                Text(summaryText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(reminder.dosageAmount)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(primaryColor)
        }
        .padding(.vertical, 3)
    }

    private var summaryText: String {
        switch reminder.frequency {
        case .daily:
            return reminder.isActive ? "Everyday" : "Paused"
        case .specificDays:
            let days = reminder.weekdays
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.shortTitle)
                .joined(separator: ", ")
            return reminder.isActive ? days : "Paused"
        case .asNeeded:
            return "As Needed"
        }
    }
}

private struct ReminderSetupView: View {
    @Environment(\.dismiss) private var dismiss

    let medicationName: String
    let originalReminder: Medication.Reminder
    var onSave: (Medication.Reminder) -> Void

    @State private var time: Date
    @State private var frequency: Medication.ReminderFrequency
    @State private var weekdays: Set<Medication.Weekday>
    @State private var isActive: Bool
    @State private var dosageAmount: Int
    @State private var isRequestingPermission = false
    @State private var isShowingPermissionAlert = false

    private let primaryColor = AppTheme.accent

    init(
        medicationName: String,
        reminder: Medication.Reminder,
        onSave: @escaping (Medication.Reminder) -> Void
    ) {
        self.medicationName = medicationName
        self.originalReminder = reminder
        self.onSave = onSave
        _time = State(initialValue: reminder.time)
        _frequency = State(initialValue: reminder.frequency)
        _weekdays = State(initialValue: reminder.weekdays.isEmpty ? Set(Medication.Weekday.allCases) : reminder.weekdays)
        _isActive = State(initialValue: reminder.isActive)
        _dosageAmount = State(initialValue: max(1, reminder.dosageAmount))
    }

    var body: some View {
        Form {
            Section(medicationName) {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)

                Stepper("Dose: \(dosageAmount)", value: $dosageAmount, in: 1...12)

                Toggle("Active", isOn: $isActive)
                    .tint(primaryColor)
            }

            Section("Frequency") {
                Picker("Frequency", selection: $frequency) {
                    ForEach(Medication.ReminderFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }

                if frequency == .specificDays {
                    WeekdayPicker(selectedWeekdays: $weekdays)
                }
            }
        }
        .navigationTitle("Reminder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isRequestingPermission ? "Saving" : "Save") {
                    Task { await save() }
                }
                .disabled(isRequestingPermission || (frequency == .specificDays && weekdays.isEmpty))
            }
        }
        .alert("Notifications Disabled", isPresented: $isShowingPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Allow notifications in Settings to schedule medication reminders.")
        }
    }

    private func save() async {
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        if isActive && frequency != .asNeeded {
            let granted = await NotificationManager.shared.requestAuthorizationIfNeeded()
            guard granted else {
                isShowingPermissionAlert = true
                return
            }
        }

        onSave(
            Medication.Reminder(
                id: originalReminder.id,
                time: time,
                frequency: frequency,
                weekdays: frequency == .specificDays ? weekdays : Set(Medication.Weekday.allCases),
                isActive: isActive,
                dosageAmount: dosageAmount
            )
        )
        dismiss()
    }
}

private extension Medication {
    var nextScheduledReminderDate: Date? {
        reminders
            .filter(\.isScheduled)
            .compactMap { $0.nextOccurrence() }
            .min()
    }
}

private extension Medication.Reminder {
    var isScheduled: Bool {
        isActive && frequency != .asNeeded
    }

    func nextOccurrence(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let components = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }

        switch frequency {
        case .daily:
            return nextOccurrence(
                from: now,
                matching: { _ in true },
                hour: hour,
                minute: minute,
                calendar: calendar
            )
        case .specificDays:
            return nextOccurrence(
                from: now,
                matching: { rawWeekday in
                    guard let weekday = Medication.Weekday(rawValue: rawWeekday) else {
                        return false
                    }
                    return weekdays.contains(weekday)
                },
                hour: hour,
                minute: minute,
                calendar: calendar
            )
        case .asNeeded:
            return nil
        }
    }

    private func nextOccurrence(
        from now: Date,
        matching isValidWeekday: (Int) -> Bool,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)

        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else {
                continue
            }

            let weekday = calendar.component(.weekday, from: day)
            guard isValidWeekday(weekday),
                  let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  candidate >= now else {
                continue
            }

            return candidate
        }

        return nil
    }
}

private struct WeekdayPicker: View {
    @Binding var selectedWeekdays: Set<Medication.Weekday>
    private let primaryColor = AppTheme.accent

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Medication.Weekday.allCases) { weekday in
                Button {
                    toggle(weekday)
                } label: {
                    Text(weekday.shortTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedWeekdays.contains(weekday) ? .white : primaryColor)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 34)
                        .background(
                            selectedWeekdays.contains(weekday) ? primaryColor : primaryColor.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekday.shortTitle)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ weekday: Medication.Weekday) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
    }
}
