import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: MedicationStore

    var body: some View {
        MedicationSelectionContainer(store: store)
    }
}

private enum MedicationTransitionDirection {
    case forward
    case backward
}

private struct MedicationSelectionContainer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let store: MedicationStore

    @StateObject private var selectionViewModel: MedicationSelectionViewModel
    @State private var transitionDirection: MedicationTransitionDirection = .forward
    @State private var isAddingMedication = false
    @State private var refillMedication: Medication?
    @State private var isShowingHistory = false
    @State private var isManagingMedications = false

    init(store: MedicationStore) {
        self.store = store
        _selectionViewModel = StateObject(wrappedValue: MedicationSelectionViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background

                if selectionViewModel.medications.isEmpty {
                    EmptyMedicationView(
                        hasDoseHistory: !store.doseRecords.isEmpty,
                        addAction: {
                            isAddingMedication = true
                        },
                        historyAction: {
                            isShowingHistory = true
                        }
                    )
                    .padding(.horizontal, 20)
                } else if let medication = selectionViewModel.selectedMedication {
                    MedicationDetailScreen(
                        medication: medication,
                        store: store,
                        pageCount: selectionViewModel.pageCount,
                        selectedIndex: selectionViewModel.selectedIndex,
                        canMovePrevious: selectionViewModel.canMovePrevious,
                        canMoveNext: selectionViewModel.canMoveNext,
                        onAddMedication: {
                            isAddingMedication = true
                        },
                        onManageMedications: {
                            isManagingMedications = true
                        },
                        onShowHistory: {
                            isShowingHistory = true
                        },
                        onRefill: { medication in
                            refillMedication = medication
                        },
                        onMovePrevious: {
                            movePreviousMedication()
                        },
                        onMoveNext: {
                            moveNextMedication()
                        }
                    )
                    .id(medication.id)
                    .transition(medicationTransition)
                    .zIndex(1)
                }
            }
            .animation(medicationTransitionAnimation, value: selectionViewModel.selectedMedicationID)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isAddingMedication) {
                AddMedicationView()
                    .environmentObject(store)
            }
            .sheet(item: $refillMedication) { medication in
                RefillView(medication: medication)
                    .environmentObject(store)
            }
            .sheet(isPresented: $isShowingHistory) {
                DoseHistoryView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $isManagingMedications) {
                ManageMedicationsView(selectedMedicationID: selectedMedicationIDBinding)
                    .environmentObject(store)
            }
            .alert(
                "Medication selection failed",
                isPresented: Binding(
                    get: { selectionViewModel.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            selectionViewModel.clearError()
                        }
                    }
                )
            ) {
                Button("OK") {
                    selectionViewModel.clearError()
                }
            } message: {
                Text(selectionViewModel.errorMessage ?? "")
            }
        }
    }

    private var selectedMedicationIDBinding: Binding<Medication.ID?> {
        Binding(
            get: {
                selectionViewModel.selectedMedicationID
            },
            set: { medicationID in
                if let medicationID {
                    selectMedication(id: medicationID)
                } else if !selectionViewModel.medications.isEmpty {
                    selectMedication(at: 0)
                }
            }
        )
    }

    private func movePreviousMedication() {
        guard selectionViewModel.canMovePrevious else { return }

        transitionDirection = .backward
        withAnimation(medicationTransitionAnimation) {
            _ = selectionViewModel.movePrevious()
        }
    }

    private func moveNextMedication() {
        guard selectionViewModel.canMoveNext else { return }

        transitionDirection = .forward
        withAnimation(medicationTransitionAnimation) {
            _ = selectionViewModel.moveNext()
        }
    }

    private func selectMedication(id medicationID: Medication.ID) {
        guard let targetIndex = selectionViewModel.medications.firstIndex(where: { $0.id == medicationID }) else {
            _ = selectionViewModel.selectMedication(id: medicationID)
            return
        }

        selectMedication(at: targetIndex)
    }

    private func selectMedication(at targetIndex: Int) {
        if let selectedIndex = selectionViewModel.selectedIndex, targetIndex != selectedIndex {
            transitionDirection = targetIndex > selectedIndex ? .forward : .backward
        }

        withAnimation(medicationTransitionAnimation) {
            _ = selectionViewModel.selectMedication(at: targetIndex)
        }
    }

    private var medicationTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var insertionEdge: Edge {
        transitionDirection == .forward ? .trailing : .leading
    }

    private var removalEdge: Edge {
        transitionDirection == .forward ? .leading : .trailing
    }

    private var medicationTransitionAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.12)
        }

        return .spring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.08)
    }

    private var background: some View {
        LinearGradient(
            colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct MedicationDetailScreen: View {
    let medication: Medication
    let pageCount: Int
    let selectedIndex: Int?
    let canMovePrevious: Bool
    let canMoveNext: Bool
    var onAddMedication: () -> Void
    var onManageMedications: () -> Void
    var onShowHistory: () -> Void
    var onRefill: (Medication) -> Void
    var onMovePrevious: () -> Void
    var onMoveNext: () -> Void

    @StateObject private var viewModel: MedicationDetailViewModel
    @State private var dosePulse = false
    private let primaryColor = AppTheme.accent
    private let medicationSwipeThreshold: CGFloat = 96

    init(
        medication: Medication,
        store: MedicationStore,
        pageCount: Int,
        selectedIndex: Int?,
        canMovePrevious: Bool,
        canMoveNext: Bool,
        onAddMedication: @escaping () -> Void,
        onManageMedications: @escaping () -> Void,
        onShowHistory: @escaping () -> Void,
        onRefill: @escaping (Medication) -> Void,
        onMovePrevious: @escaping () -> Void,
        onMoveNext: @escaping () -> Void
    ) {
        self.medication = medication
        self.pageCount = pageCount
        self.selectedIndex = selectedIndex
        self.canMovePrevious = canMovePrevious
        self.canMoveNext = canMoveNext
        self.onAddMedication = onAddMedication
        self.onManageMedications = onManageMedications
        self.onShowHistory = onShowHistory
        self.onRefill = onRefill
        self.onMovePrevious = onMovePrevious
        self.onMoveNext = onMoveNext
        self._viewModel = StateObject(wrappedValue: MedicationDetailViewModel(medication: medication, store: store))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 8) {
                    if pageCount > 1 {
                        MedicationPageIndicator(
                            pageCount: pageCount,
                            selectedIndex: selectedIndex ?? 0
                        )
                        .padding(.bottom, 6)
                    }

                    if let snapshot = viewModel.snapshot {
                        MedicationDetailHeroSection(
                            snapshot: snapshot,
                            sceneHeight: bottleSceneHeight(for: geometry),
                            isPulsing: dosePulse
                        )

                        MedicationMetricsGrid(metrics: snapshot.metrics)

                        MedicationReminderCard(overview: snapshot.reminderOverview)

                        RecentDoseRecordsCard(
                            records: snapshot.recentDoseRecords,
                            onShowHistory: onShowHistory
                        )
                    } else {
                        MedicationDetailLoadingCard()
                            .padding(.top, 36)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 112)
            }
            .refreshable {
                await viewModel.refresh()
            }
            .simultaneousGesture(medicationSwipeGesture)
            .accessibilityLabel("Medication detail")
            .accessibilityValue(accessibilitySelectionValue)
            .accessibilityHint(accessibilitySelectionHint)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onMoveNext()
                case .decrement:
                    onMovePrevious()
                @unknown default:
                    break
                }
            }
            .task(id: medication.id) {
                await viewModel.refresh()
            }
            .onChange(of: medication) { _, _ in
                viewModel.load()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                MedicationDetailToolbar(
                    onAddMedication: onAddMedication,
                    onManageMedications: onManageMedications,
                    onShowHistory: onShowHistory
                )
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(.clear)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let snapshot = viewModel.snapshot {
                    MedicationDetailActionBar(
                        actions: snapshot.actions,
                        isLoading: viewModel.isLoading,
                        primaryColor: primaryColor,
                        primaryAction: {
                            handlePrimaryAction(snapshot)
                        },
                        refillAction: {
                            onRefill(snapshot.medication)
                        }
                    )
                }
            }
            .alert(
                "Medication update failed",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.clearError()
                        }
                    }
                )
            ) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func bottleSceneHeight(for geometry: GeometryProxy) -> CGFloat {
        min(236, max(212, geometry.size.height * 0.27))
    }

    private var medicationSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                handleMedicationSwipe(value)
            }
    }

    private var accessibilitySelectionValue: String {
        guard pageCount > 1, let selectedIndex else {
            return medication.name
        }

        return "\(medication.name), medication \(selectedIndex + 1) of \(pageCount)"
    }

    private var accessibilitySelectionHint: String {
        guard pageCount > 1 else {
            return "Current medication details."
        }

        return "Swipe left or right with one finger to switch medications. Swipe up or down with VoiceOver to change medications."
    }

    private func handleMedicationSwipe(_ value: DragGesture.Value) {
        guard pageCount > 1 else { return }

        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height
        let predictedHorizontalDistance = value.predictedEndTranslation.width
        let effectiveHorizontalDistance = abs(predictedHorizontalDistance) > abs(horizontalDistance)
            ? predictedHorizontalDistance
            : horizontalDistance

        guard abs(effectiveHorizontalDistance) >= medicationSwipeThreshold else { return }
        guard abs(horizontalDistance) > abs(verticalDistance) * 1.5 else { return }

        if effectiveHorizontalDistance < 0 {
            onMoveNext()
        } else {
            onMovePrevious()
        }
    }

    private func handlePrimaryAction(_ snapshot: MedicationDetailSnapshot) {
        guard snapshot.actions.canLogDose else {
            onRefill(snapshot.medication)
            return
        }

        dosePulse = true
        viewModel.logDose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                dosePulse = false
            }
        }
    }
}

private struct MedicationPageIndicator: View {
    let pageCount: Int
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? AppTheme.accent : AppTheme.accent.opacity(0.22))
                    .frame(width: index == selectedIndex ? 18 : 6, height: 6)
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

private struct MedicationDetailToolbar: View {
    private let primaryColor = AppTheme.accent
    var onAddMedication: () -> Void
    var onManageMedications: () -> Void
    var onShowHistory: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pills.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(primaryColor)
                .frame(width: 42, height: 42)
                .accessibilityLabel("Current medication")

            Spacer()

            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    toolbarButtons
                }
            } else {
                toolbarButtons
            }
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        HStack(spacing: 10) {
            ToolbarIconButton(
                systemImage: "plus",
                label: "Add medication",
                hint: "Opens the form to add another medication.",
                isPrimary: true,
                action: onAddMedication
            )
            ToolbarIconButton(
                systemImage: "list.bullet",
                label: "Manage medications",
                hint: "Opens medication management.",
                action: onManageMedications
            )
            ToolbarIconButton(
                systemImage: "calendar",
                label: "Dose history",
                hint: "Shows logged doses.",
                action: onShowHistory
            )
        }
    }
}

private struct ToolbarIconButton: View {
    let systemImage: String
    let label: String
    let hint: String
    var isPrimary = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
        }
        .liquidGlassStyle(
            tint: AppTheme.accent,
            isProminent: isPrimary,
            size: 42
        )
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

struct LiquidGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var tint: Color = AppTheme.accent
    var isProminent = false
    var size: CGFloat = 44

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            nativeGlassBody(configuration: configuration)
        } else {
            fallbackBody(configuration: configuration)
        }
    }

    @available(iOS 26.0, *)
    private func nativeGlassBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isProminent ? .white : tint)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .glassEffect(
                glassEffect,
                in: .circle
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }

    private func fallbackBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(isProminent ? tint : AppTheme.primaryText, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.92), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
    }

    @available(iOS 26.0, *)
    private var glassEffect: Glass {
        if isProminent {
            return .clear.tint(tint.opacity(0.7)).interactive()
        }

        return .regular.interactive()
    }
}

extension View {
    func liquidGlassStyle(
        tint: Color = AppTheme.accent,
        isProminent: Bool = false,
        size: CGFloat = 44
    ) -> some View {
        buttonStyle(
            LiquidGlassButtonStyle(
                tint: tint,
                isProminent: isProminent,
                size: size
            )
        )
    }
}

struct LiquidGlassButtonStyleExampleContentView: View {
    var body: some View {
        ZStack {
            abstractBackground

            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 18) {
                    exampleButtons
                }
            } else {
                exampleButtons
            }
        }
    }

    private var exampleButtons: some View {
        HStack(spacing: 18) {
            Button {} label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
            }
            .liquidGlassStyle(tint: .mint, isProminent: true, size: 52)
            .accessibilityLabel("Add")

            Button {} label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .bold))
            }
            .liquidGlassStyle(tint: .cyan, size: 52)
            .accessibilityLabel("List")

            Button {} label: {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .bold))
            }
            .liquidGlassStyle(tint: .pink, size: 52)
            .accessibilityLabel("Calendar")
        }
    }

    private var abstractBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.12, blue: 0.30),
                    Color(red: 0.00, green: 0.55, blue: 0.74),
                    Color(red: 0.88, green: 0.24, blue: 0.48)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.yellow.opacity(0.55))
                .frame(width: 210, height: 210)
                .blur(radius: 18)
                .offset(x: -92, y: -132)

            Circle()
                .fill(Color.purple.opacity(0.56))
                .frame(width: 240, height: 240)
                .blur(radius: 24)
                .offset(x: 112, y: 138)

            RoundedRectangle(cornerRadius: 48)
                .fill(Color.white.opacity(0.18))
                .frame(width: 260, height: 92)
                .rotationEffect(.degrees(-18))
                .offset(x: 20, y: -8)
        }
        .ignoresSafeArea()
    }
}

#Preview("Liquid Glass Buttons") {
    LiquidGlassButtonStyleExampleContentView()
}

private struct MedicationDetailHeroSection: View {
    let snapshot: MedicationDetailSnapshot
    let sceneHeight: CGFloat
    let isPulsing: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            heroText(alignment: .center, textAlignment: .center, titleSize: 24)
                .frame(maxWidth: 340, alignment: .center)
                .padding(.bottom, 24)

            bottleStage
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(AppTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.separator, lineWidth: 1)
        }
    }

    private func heroText(
        alignment: HorizontalAlignment,
        textAlignment: TextAlignment,
        titleSize: CGFloat
    ) -> some View {
        VStack(alignment: alignment, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: snapshot.hero.bottleColorHex))
                    .frame(width: 11, height: 11)

                Text("\(snapshot.hero.classificationText) \(snapshot.hero.shapeText)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Text(snapshot.hero.name)
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(textAlignment)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bottleScene(height: CGFloat) -> some View {
        BottleSceneView(medication: snapshot.medication)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .scaleEffect(isPulsing ? 0.985 : 1)
            .accessibilityLabel("\(snapshot.hero.name) bottle visualization")
            .accessibilityHint("Drag horizontally to rotate the bottle.")
    }

    private var bottleStage: some View {
        bottleScene(height: sceneHeight)
            .frame(maxWidth: 360, alignment: .center)
            .frame(height: sceneHeight, alignment: .center)
            .clipped()
    }
}

private struct MedicationMetricsGrid: View {
    let metrics: [MedicationDetailMetric]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(metrics) { metric in
                MedicationMetricCard(metric: metric)
            }
        }
    }
}

private struct MedicationMetricCard: View {
    let metric: MedicationDetailMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)

            Text(metric.value)
                .font(.system(size: metric.kind == .lastTaken ? 20 : 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            if let subtitle = metric.subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct MedicationReminderCard: View {
    let overview: MedicationReminderOverview

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminderIcon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(accentColor)
                .frame(width: 34, height: 34)
                .background(accentColor.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminderLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)

                Text(overview.activeCount > 0 ? "Reminder" : overview.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 12)

            Text(reminderTimeText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reminderLabel), \(reminderTimeText)")
    }

    private var accentColor: Color {
        overview.activeCount > 0 ? AppTheme.accent : AppTheme.tertiaryText
    }

    private var reminderIcon: String {
        overview.activeCount > 0 ? "bell.fill" : "bell.slash.fill"
    }

    private var reminderLabel: String {
        overview.activeCount > 0 ? "Next Dose" : "No Reminder"
    }

    private var reminderTimeText: String {
        guard let nextReminderText = overview.nextReminderText else {
            return "Not set"
        }

        if let separatorRange = nextReminderText.range(of: " at ", options: [.backwards]) {
            return String(nextReminderText[separatorRange.upperBound...])
        }

        return nextReminderText.replacingOccurrences(of: "Next: ", with: "")
    }
}

private struct RecentDoseRecordsCard: View {
    let records: [DoseRecord]
    var onShowHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent doses")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Button(action: onShowHistory) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.accent.opacity(0.10), in: Circle())
                }
                .accessibilityLabel("Show dose history")
                .accessibilityHint("Opens the full dose history.")
            }

            if records.isEmpty {
                Text("No doses logged yet")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(records.prefix(3)) { record in
                        RecentDoseRecordRow(record: record)
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RecentDoseRecordRow: View {
    let record: DoseRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(AppTheme.accent, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.takenAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("\(record.tabletCount) tablet\(record.tabletCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MedicationDetailActionBar: View {
    let actions: MedicationDetailActions
    let isLoading: Bool
    let primaryColor: Color
    var primaryAction: () -> Void
    var refillAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: primaryAction) {
                Label(actions.primaryTitle, systemImage: actions.primarySystemImage)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(primaryColor, in: RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isLoading)
            .accessibilityLabel(actions.primaryTitle)
            .accessibilityHint(actions.canLogDose ? "Logs the scheduled dose for this medication." : "Opens refill options for this medication.")

            Button(action: refillAction) {
                Image(systemName: actions.refillSystemImage)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(primaryColor)
                    .frame(width: 54, height: 54)
                    .background(AppTheme.controlSurface, in: RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isLoading || !actions.canRefill)
            .accessibilityLabel(actions.refillTitle)
            .accessibilityHint("Opens refill options for this medication.")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

private struct MedicationDetailLoadingCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.accent)

            Text("Loading medication details")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatPill: View {
    let title: String
    let value: String
    private let titleColor = AppTheme.secondaryText

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(titleColor)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    private let titleColor = AppTheme.secondaryText

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(titleColor)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RefillInfoCard: View {
    let accentColor: Color
    private let titleColor = AppTheme.secondaryText

    var body: some View {
        VStack(spacing: 3) {
            Text("Bottle")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(titleColor)

            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .bold))
                Text("Refill")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(accentColor)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.36), lineWidth: 1)
        }
    }
}

struct EmptyMedicationView: View {
    let hasDoseHistory: Bool
    var addAction: () -> Void
    var historyAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "pills.fill")
                .font(.system(size: 62))
                .foregroundStyle(AppTheme.accent)
            Text("Add your first bottle")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Button("Add Medication", action: addAction)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens the form to add your first medication.")

            if hasDoseHistory {
                Button(action: historyAction) {
                    Label("View Dose History", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("View preserved dose history")
                .accessibilityHint("Opens dose history from medications that may no longer be active.")
            }
            Spacer()
        }
    }
}
