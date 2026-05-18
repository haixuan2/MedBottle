import SwiftUI

struct ManageMedicationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MedicationStore

    @Binding var selectedMedicationID: Medication.ID?
    @State private var reminderSelection: ReminderMedicationSelection?

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
                        ForEach(store.medications) { medication in
                            HStack(spacing: 10) {
                                NavigationLink {
                                    MedicationEditorView(medication: medication)
                                        .environmentObject(store)
                                } label: {
                                    MedicationManagementRow(medication: medication)
                                }

                                ReminderStatusButton(medication: medication) {
                                    reminderSelection = ReminderMedicationSelection(id: medication.id)
                                }
                            }
                        }
                        .onDelete(perform: deleteMedications)
                    }
                }
            }
            .navigationTitle("Manage Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !store.medications.isEmpty {
                        EditButton()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $reminderSelection) { selection in
                MedicationReminderManagementView(medicationID: selection.id)
                    .environmentObject(store)
            }
        }
    }

    private func deleteMedications(at offsets: IndexSet) {
        selectedMedicationID = store.deleteMedications(
            at: offsets,
            selectedID: selectedMedicationID
        )
    }
}

private struct ReminderMedicationSelection: Identifiable {
    let id: Medication.ID
}

private struct MedicationManagementRow: View {
    let medication: Medication
    private let primaryColor = AppTheme.accent

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: medication.bottleColorHex))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("\(medication.medicationShape.title) • \(medication.classification.title)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(medication.remainingText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryColor)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ReminderStatusButton: View {
    let medication: Medication
    let action: () -> Void

    private let primaryColor = AppTheme.accent

    private var activeReminderCount: Int {
        medication.reminders.filter { $0.isScheduled }.count
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: activeReminderCount > 0 ? "bell.fill" : "bell.badge")
                    .font(.system(size: 15, weight: .bold))

                Text(statusText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(activeReminderCount > 0 ? .white : primaryColor)
            .frame(width: 92)
            .padding(.vertical, 8)
            .background(
                activeReminderCount > 0 ? primaryColor : primaryColor.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var statusText: String {
        guard let nextDate = medication.nextScheduledReminderDate else {
            return "Add"
        }

        return "Next: \(nextDate.formatted(date: .omitted, time: .shortened))"
    }

    private var accessibilityText: String {
        guard let nextDate = medication.nextScheduledReminderDate else {
            return "Add reminder for \(medication.name)"
        }

        let nextTime = nextDate.formatted(date: .omitted, time: .shortened)
        return "Manage reminders for \(medication.name). Next reminder at \(nextTime)"
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
    @State private var customColor: Color
    @State private var medicationShape: MedicationShape
    @State private var medicationClassification: MedicationClassification
    @State private var reminders: [Medication.Reminder]

    private let colors = ["D99A00", "C87B00", "8FB7D8", "74A88D", "D35F7B"]
    private let primaryColor = AppTheme.accent

    init(medication: Medication) {
        self.medication = medication
        _name = State(initialValue: medication.name)
        _tabletCount = State(initialValue: medication.tabletsRemaining)
        _doseCount = State(initialValue: medication.tabletsPerDose)
        _colorHex = State(initialValue: medication.bottleColorHex)
        _customColor = State(initialValue: Color(hex: medication.bottleColorHex))
        _medicationShape = State(initialValue: medication.medicationShape)
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
            }

            MedicationReminderSection(
                medicationName: reminderMedicationName,
                dosageAmount: doseCount,
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
                medicationShape: medicationShape,
                classification: medicationClassification,
                reminders: reminders,
                lastTakenAt: medication.lastTakenAt
            )
        )
    }

    private var reminderMedicationName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Medication" : trimmedName
    }
}

private struct MedicationReminderManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MedicationStore

    let medicationID: Medication.ID

    private var medication: Medication? {
        store.medications.first { $0.id == medicationID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let medication {
                    MedicationReminderSection(
                        medicationName: medication.name,
                        dosageAmount: medication.tabletsPerDose,
                        reminders: remindersBinding(for: medication)
                    )
                } else {
                    ContentUnavailableView(
                        "Medication unavailable",
                        systemImage: "pills",
                        description: Text("This medication may have been deleted.")
                    )
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func remindersBinding(for medication: Medication) -> Binding<[Medication.Reminder]> {
        Binding {
            store.medications.first { $0.id == medication.id }?.reminders ?? medication.reminders
        } set: { reminders in
            guard var updatedMedication = store.medications.first(where: { $0.id == medication.id }) else {
                return
            }
            updatedMedication.reminders = reminders
            store.updateMedication(updatedMedication)
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
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.vertical, 11)
                .padding(.horizontal, 12)
                .background(primaryColor, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Label("Add Reminder", systemImage: "bell.badge")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Text(summaryText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(reminder.dosageAmount)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
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
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedWeekdays.contains(weekday) ? .white : primaryColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
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
