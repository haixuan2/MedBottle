import SwiftUI

struct DoseHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MedicationStore

    @State private var selectedMedicationID: Medication.ID?
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var pendingDeletion: DoseRecord?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    init(initialMedicationID: Medication.ID? = nil) {
        _selectedMedicationID = State(initialValue: initialMedicationID)
    }

    private var adherence: MedicationAdherenceCalculator {
        MedicationAdherenceCalculator(calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 22) {
                        monthHeader
                        archivedMedicationNotice
                        weekdayHeader
                        monthGrid
                        selectedDaySummary
                    }
                    .padding(.vertical, 8)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 6, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                recordsSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundTop)
            .safeAreaInset(edge: .top, spacing: 0) {
                if store.medications.count > 1 {
                    medicationFilterRow
                }
            }
            .navigationTitle("Dose History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this dose record?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented { pendingDeletion = nil }
                    }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { record in
                Button("Delete", role: .destructive) {
                    delete(record, returningTablets: false)
                }
                Button(returnTabletsTitle(for: record)) {
                    delete(record, returningTablets: true)
                }
                Button("Cancel", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: { record in
                Text(deletionMessage(for: record))
            }
        }
        .onAppear {
            if let latest = displayedRecords.map(\.takenAt).max() {
                selectedDate = latest
                visibleMonth = latest
            }
        }
    }

    // MARK: - Medication filter

    private var medicationFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", color: nil, isSelected: selectedMedicationID == nil) {
                    selectedMedicationID = nil
                }

                ForEach(store.medications) { medication in
                    filterChip(
                        title: medication.name,
                        color: Color(hex: medication.bottleColorHex),
                        isSelected: selectedMedicationID == medication.id
                    ) {
                        selectedMedicationID = medication.id
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(AppTheme.backgroundTop)
    }

    private func filterChip(
        title: String,
        color: Color?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color {
                    Circle()
                        .fill(isSelected ? Color.white : color)
                        .frame(width: 8, height: 8)
                }

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : AppTheme.primaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(isSelected ? AppTheme.accent : AppTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color == nil ? "All medications" : title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Calendar

    private var monthHeader: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 38, height: 38)
                    .background(AppTheme.controlSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Spacer()

            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 38, height: 38)
                    .background(AppTheme.controlSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol.prefix(1))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 18)
            }
        }
    }

    private var monthGrid: some View {
        let countsByDay = doseCountsByDay
        let medications = scopedMedications

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(monthDays, id: \.self) { day in
                if let day {
                    DayCell(
                        date: day,
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(day),
                        status: adherence.dayStatus(
                            expectedDoses: adherence.expectedDoseCount(for: medications, on: day),
                            loggedDoses: countsByDay[calendar.startOfDay(for: day), default: 0],
                            on: day
                        )
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedDate = day
                        }
                    }
                } else {
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
    }

    private var selectedDaySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(selectedDaySummaryText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text("\(selectedDayTabletTotal)")
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityLabel("\(selectedDayTabletTotal) tablet\(selectedDayTabletTotal == 1 ? "" : "s") taken")
            }

            if currentStreak > 0 {
                Label("\(currentStreak) day streak", systemImage: "flame.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityLabel("Current streak, \(currentStreak) day\(currentStreak == 1 ? "" : "s")")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medicationCardSurface(.secondary, borderOpacity: 0)
    }

    private var recordsSection: some View {
        Section {
            if selectedDayRecords.isEmpty {
                ContentUnavailableView(
                    "No doses recorded",
                    systemImage: "calendar.badge.clock",
                    description: Text("Recorded doses for this day will appear here.")
                )
                .padding(.vertical, 24)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(selectedDayRecords) { record in
                    DoseRecordRow(
                        record: record,
                        isMedicationActive: activeMedicationIDs.contains(record.medicationID)
                    )
                        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeletion = record
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: - Data

    /// The medications the current filter covers — one, or every active medication.
    private var scopedMedications: [Medication] {
        guard let selectedMedicationID else { return store.medications }
        return store.medications.filter { $0.id == selectedMedicationID }
    }

    private var displayedRecords: [DoseRecord] {
        guard let selectedMedicationID else { return store.doseRecords }
        return store.doseRecords.filter { $0.medicationID == selectedMedicationID }
    }

    private var activeMedicationIDs: Set<Medication.ID> {
        Set(store.medications.map(\.id))
    }

    private var isShowingDeletedMedicationHistory: Bool {
        guard let selectedMedicationID else { return false }
        return !activeMedicationIDs.contains(selectedMedicationID) && !displayedRecords.isEmpty
    }

    @ViewBuilder
    private var archivedMedicationNotice: some View {
        if isShowingDeletedMedicationHistory {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "archivebox")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Deleted medication")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("Preserved doses are shown using the medication name saved with each record.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .medicationCardSurface(.tertiary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Deleted medication history")
            .accessibilityHint("Dose records are preserved and use the medication name saved at the time they were recorded.")
        }
    }

    private var selectedDayRecords: [DoseRecord] {
        recordsByDay[calendar.startOfDay(for: selectedDate), default: []]
            .sorted { $0.takenAt > $1.takenAt }
    }

    private var selectedDayTabletTotal: Int {
        selectedDayRecords.reduce(0) { $0 + $1.tabletCount }
    }

    private var selectedDaySummaryText: String {
        let doseCount = selectedDayRecords.count
        let doseText = "\(doseCount) dose\(doseCount == 1 ? "" : "s")"
        let expected = adherence.expectedDoseCount(for: scopedMedications, on: selectedDate)

        if expected > 0 {
            return "\(doseCount) of \(expected) doses recorded"
        }

        guard selectedMedicationID == nil, doseCount > 0 else {
            return "\(doseText) recorded"
        }

        let medicationCount = Set(selectedDayRecords.map(\.medicationID)).count
        return "\(doseText) across \(medicationCount) medication\(medicationCount == 1 ? "" : "s")"
    }

    private var currentStreak: Int {
        adherence.currentStreak(
            medications: scopedMedications,
            loggedDosesByDay: doseCountsByDay
        )
    }

    private var monthDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dates = dayRange.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start)
        }

        return Array(repeating: nil, count: leadingBlanks) + dates
    }

    private var recordsByDay: [Date: [DoseRecord]] {
        Dictionary(grouping: displayedRecords) { record in
            calendar.startOfDay(for: record.takenAt)
        }
    }

    private var doseCountsByDay: [Date: Int] {
        recordsByDay.mapValues(\.count)
    }

    private func moveMonth(by amount: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: amount, to: visibleMonth) else { return }
        visibleMonth = nextMonth
        if let monthInterval = calendar.dateInterval(of: .month, for: nextMonth),
           !monthInterval.contains(selectedDate) {
            selectedDate = monthInterval.start
        }
    }

    // MARK: - Deletion

    private func returnTabletsTitle(for record: DoseRecord) -> String {
        let count = max(1, record.tabletCount)
        return "Delete and return \(count) tablet\(count == 1 ? "" : "s") to the bottle"
    }

    private func deletionMessage(for record: DoseRecord) -> String {
        let count = max(1, record.tabletCount)
        let dayText = record.takenAt.formatted(.dateTime.month(.abbreviated).day())
        let timeText = record.takenAt.formatted(date: .omitted, time: .shortened)
        return "\(record.medicationName), \(count) tablet\(count == 1 ? "" : "s"), \(dayText) at \(timeText)."
    }

    private func delete(_ record: DoseRecord, returningTablets: Bool) {
        store.deleteDoseRecords(withIDs: [record.id], returningTablets: returningTablets)
        pendingDeletion = nil
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let status: MedicationDayStatus
    var action: () -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(.semibold))
                marker
            }
            .foregroundStyle(isSelected ? .white : AppTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.accent, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Complete fills, partial half-fills, missed rings, nothing expected shows nothing.
    @ViewBuilder
    private var marker: some View {
        switch status.adherence {
        case .complete:
            Circle()
                .fill(markerColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        case .partial:
            ZStack(alignment: .leading) {
                Circle()
                    .fill(markerColor.opacity(0.2))
                    .frame(width: 6, height: 6)

                Circle()
                    .fill(markerColor)
                    .frame(width: 6, height: 6)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: 3)
                    }
            }
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
        case .missed:
            Circle()
                .strokeBorder(isSelected ? Color.white : AppTheme.warning, lineWidth: 1.5)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        case .none:
            Color.clear
                .frame(width: 6, height: 6)
        }
    }

    private var markerColor: Color {
        isSelected ? .white : AppTheme.accent
    }

    private var backgroundStyle: Color {
        if isSelected {
            return AppTheme.accent
        }
        return status.loggedDoses > 0 ? AppTheme.surfaceStrong : AppTheme.surfaceSubtle
    }

    private var accessibilityLabel: String {
        let dateText = date.formatted(.dateTime.month(.wide).day().year())
        return "\(dateText)\(status.accessibilitySuffix)"
    }
}

private struct DoseRecordRow: View {
    let record: DoseRecord
    let isMedicationActive: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(record.takenAt.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                Text(record.takenAt.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 76)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.medicationName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text("\(record.tabletCount) tablet\(record.tabletCount == 1 ? "" : "s") taken")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    if !isMedicationActive {
                        Text("Deleted")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.accent.opacity(0.10), in: Capsule())
                    }
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.accent)
        }
        .padding(14)
        .medicationCardSurface(.tertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityLabel: String {
        let doseText = "\(record.tabletCount) tablet\(record.tabletCount == 1 ? "" : "s") taken"
        let timeText = record.takenAt.formatted(date: .abbreviated, time: .shortened)
        let statusText = isMedicationActive ? "active medication" : "deleted medication"
        return "\(record.medicationName), \(doseText), \(timeText), \(statusText)"
    }

    private var accessibilityHint: String {
        isMedicationActive
            ? "Historical dose record."
            : "This preserved dose record belongs to a medication that is no longer active."
    }
}
