import SwiftUI

struct DoseHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MedicationStore

    let initialMedicationID: Medication.ID? = nil
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

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
            .navigationTitle("Dose History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if let latest = displayedRecords.map(\.takenAt).max() {
                selectedDate = latest
                visibleMonth = latest
            }
        }
    }

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
                .font(.system(size: 22, weight: .bold, design: .rounded))
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
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(height: 18)
            }
        }
    }

    private var monthGrid: some View {
        let countsByDay = doseCountsByDay

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(monthDays, id: \.self) { day in
                if let day {
                    DayCell(
                        date: day,
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(day),
                        doseCount: countsByDay[calendar.startOfDay(for: day), default: 0]
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(selectedDaySummaryText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(selectedDayTabletTotal)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .accessibilityLabel("\(selectedDayTabletTotal) tablet\(selectedDayTabletTotal == 1 ? "" : "s") taken")
        }
        .padding(16)
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 8))
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
                }
                .onDelete(perform: deleteSelectedDayDoseRecords)
            }
        }
    }

    private var displayedRecords: [DoseRecord] {
        guard let initialMedicationID else { return store.doseRecords }
        return store.doseRecords.filter { $0.medicationID == initialMedicationID }
    }

    private var activeMedicationIDs: Set<Medication.ID> {
        Set(store.medications.map(\.id))
    }

    private var isShowingDeletedMedicationHistory: Bool {
        guard let initialMedicationID else { return false }
        return !activeMedicationIDs.contains(initialMedicationID) && !displayedRecords.isEmpty
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
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("Preserved doses are shown using the medication name saved with each record.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
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
        guard initialMedicationID == nil, doseCount > 0 else {
            return "\(doseText) recorded"
        }

        let medicationCount = Set(selectedDayRecords.map(\.medicationID)).count
        return "\(doseText) across \(medicationCount) medication\(medicationCount == 1 ? "" : "s")"
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

    private func deleteSelectedDayDoseRecords(at offsets: IndexSet) {
        let records = selectedDayRecords
        let recordIDs = Set(
            offsets.compactMap { offset in
                records.indices.contains(offset) ? records[offset].id : nil
            }
        )

        store.deleteDoseRecords(withIDs: recordIDs)
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let doseCount: Int
    var action: () -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                if doseCount > 0 {
                    Circle()
                        .fill(isSelected ? .white : AppTheme.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                } else {
                    Color.clear
                        .frame(width: 6, height: 6)
                }
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

    private var backgroundStyle: Color {
        if isSelected {
            return AppTheme.accent
        }
        return doseCount > 0 ? AppTheme.surfaceStrong : AppTheme.surfaceSubtle
    }

    private var accessibilityLabel: String {
        let dateText = date.formatted(.dateTime.month(.wide).day().year())
        return "\(dateText), \(doseCount) dose\(doseCount == 1 ? "" : "s")"
    }
}

private struct DoseRecordRow: View {
    let record: DoseRecord
    let isMedicationActive: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(record.takenAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(record.takenAt.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 76)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.medicationName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                HStack(spacing: 8) {
                    Text("\(record.tabletCount) tablet\(record.tabletCount == 1 ? "" : "s") taken")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    if !isMedicationActive {
                        Text("Deleted")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
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
        .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 8))
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
