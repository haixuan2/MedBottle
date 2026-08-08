import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: MedicationStore

    var body: some View {
        MedicationSelectionContainer(store: store)
            .fontDesign(.rounded)
    }
}

/// Carries which medication history opens for, so the filter is set at presentation
/// time rather than racing a separate `isPresented` flag.
private struct DoseHistoryPresentation: Identifiable {
    let medicationID: Medication.ID?
    var id: String { medicationID?.uuidString ?? "all" }
}

extension String {
    /// Lowercases a leading word only when it is not a proper noun, so
    /// "Runs out Aug 24" reads inline without touching "Aug".
    var lowercasedSentence: String {
        guard let first = first, first.isUppercase else { return self }
        return first.lowercased() + dropFirst()
    }
}

/// The three card weights defined by the design review. Every card in the app draws
/// its surface through this modifier so the tiers stay consistent.
enum MedicationCardTier {
    case primary    // today verdict — tinted, 22pt, 1pt tint border
    case secondary  // stock — surfaceStrong, 22pt, 1pt status border
    case tertiary   // reminder, dose history — surface, 18pt, no border

    var cornerRadius: CGFloat {
        switch self {
        case .primary, .secondary: 22
        case .tertiary: 18
        }
    }

    var defaultBorderOpacity: Double {
        switch self {
        case .primary: 0.24
        case .secondary: 0.22
        case .tertiary: 0
        }
    }
}

struct MedicationCardSurface: ViewModifier {
    let tier: MedicationCardTier
    var fill: Color?
    var borderTint: Color = AppTheme.accent
    var borderOpacity: Double?
    var borderWidth: CGFloat = 1

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: tier.cornerRadius, style: .continuous)
        let opacity = borderOpacity ?? tier.defaultBorderOpacity

        return content
            .background(fill ?? defaultFill, in: shape)
            .overlay {
                if opacity > 0 {
                    shape.strokeBorder(borderTint.opacity(opacity), lineWidth: borderWidth)
                }
            }
    }

    private var defaultFill: Color {
        switch tier {
        case .primary: AppTheme.accent.opacity(0.10)
        case .secondary: AppTheme.surfaceStrong
        case .tertiary: AppTheme.surface
        }
    }
}

extension View {
    func medicationCardSurface(
        _ tier: MedicationCardTier,
        fill: Color? = nil,
        borderTint: Color = AppTheme.accent,
        borderOpacity: Double? = nil,
        borderWidth: CGFloat = 1
    ) -> some View {
        modifier(
            MedicationCardSurface(
                tier: tier,
                fill: fill,
                borderTint: borderTint,
                borderOpacity: borderOpacity,
                borderWidth: borderWidth
            )
        )
    }
}

struct RefillView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MedicationStore

    let medication: Medication
    @State private var tabletQuantity: MedicationQuantityInputState

    init(medication: Medication) {
        self.medication = medication
        _tabletQuantity = State(initialValue: MedicationQuantityInputConfiguration.tabletCount.makeState(value: medication.tabletsRemaining))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(medication.name) {
                    MedicationQuantityInputRow(
                        title: "Tablets",
                        quantity: $tabletQuantity
                    )

                    Text("Current bottle count: \(medication.remainingText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Current bottle count")
                        .accessibilityValue(medication.remainingText)
                }
            }
            .navigationTitle("Refill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.refill(
                            medication,
                            to: tabletQuantity.value ?? MedicationQuantityLimits.tabletCount.lowerBound
                        )
                        dismiss()
                    }
                    .disabled(!tabletQuantity.isValid)
                }
            }
        }
    }
}

struct ManualDoseLogView: View {
    @Environment(\.dismiss) private var dismiss

    let medication: Medication
    let latestAllowedDate: Date
    var onSave: (Date) -> Void

    @State private var takenAt: Date

    init(
        medication: Medication,
        initialTakenAt: Date = Date(),
        latestAllowedDate: Date = Date(),
        onSave: @escaping (Date) -> Void
    ) {
        self.medication = medication
        self.latestAllowedDate = latestAllowedDate
        self.onSave = onSave
        _takenAt = State(initialValue: min(initialTakenAt, latestAllowedDate))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    LabeledContent("Name", value: medication.name)
                    LabeledContent("Current bottle count", value: medication.remainingText)
                }

                Section("Dose") {
                    LabeledContent("Tablets taken", value: doseText)
                }

                Section("Taken") {
                    DatePicker(
                        "Date and time",
                        selection: $takenAt,
                        in: ...latestAllowedDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityLabel("Taken date and time")
                    .accessibilityHint("Choose when this dose was taken.")
                }
            }
            .navigationTitle("Add Taken Dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        takenAt <= latestAllowedDate
    }

    private var doseText: String {
        "\(medication.tabletsPerDose) tablet\(medication.tabletsPerDose == 1 ? "" : "s")"
    }

    private func save() {
        guard canSave else { return }
        onSave(takenAt)
        dismiss()
    }
}

private struct MedicationSelectionContainer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let store: MedicationStore

    @StateObject private var selectionViewModel: MedicationSelectionViewModel
    /// The page the pager is actually resting on. Kept in sync with the view model's
    /// selection in both directions: a swipe writes here first, a programmatic
    /// selection (Manage sheet, VoiceOver) writes there first.
    @State private var scrolledMedicationID: Medication.ID?
    @State private var isAddingMedication = false
    @State private var refillMedication: Medication?
    @State private var historyPresentation: DoseHistoryPresentation?
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
                            historyPresentation = DoseHistoryPresentation(medicationID: nil)
                        }
                    )
                    .padding(.horizontal, 20)
                } else {
                    medicationPager
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isAddingMedication) {
                AddMedicationView()
                    .environmentObject(store)
            }
            .sheet(item: $refillMedication) { medication in
                RefillView(medication: medication)
                    .environmentObject(store)
            }
            .sheet(item: $historyPresentation) { presentation in
                DoseHistoryView(initialMedicationID: presentation.medicationID)
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

    /// One full-width page per medication on the system's paging scroll, so the screens
    /// track the finger, rubber-band at the ends and settle with the gesture's velocity.
    /// Pages hold their own view models for as long as they live, so swiping back is
    /// instant instead of rebuilding the screen and re-reading its snapshot.
    private var medicationPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(selectionViewModel.medications.enumerated()), id: \.element.id) { index, medication in
                    MedicationDetailScreen(
                        medication: medication,
                        store: store,
                        pageCount: selectionViewModel.pageCount,
                        selectedIndex: index,
                        onAddMedication: {
                            isAddingMedication = true
                        },
                        onManageMedications: {
                            isManagingMedications = true
                        },
                        onShowHistory: {
                            historyPresentation = DoseHistoryPresentation(medicationID: medication.id)
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
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledMedicationID)
        .scrollIndicators(.hidden)
        // A single medication has nowhere to page to; without this it still rubber-bands.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .onAppear {
            scrolledMedicationID = selectionViewModel.selectedMedicationID
        }
        .onChange(of: scrolledMedicationID) { _, settledID in
            guard let settledID, settledID != selectionViewModel.selectedMedicationID else { return }
            // The scroll already animated the change; re-animating it here would fight it.
            selectionViewModel.selectMedication(id: settledID)
        }
        .onChange(of: selectionViewModel.selectedMedicationID) { _, selectedID in
            guard let selectedID, selectedID != scrolledMedicationID else { return }
            withAnimation(pageScrollAnimation) {
                scrolledMedicationID = selectedID
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

    // Selection changes that do not come from the finger still move the pager: they
    // write the selection, and the pager scrolls itself to match.
    private func movePreviousMedication() {
        _ = selectionViewModel.movePrevious()
    }

    private func moveNextMedication() {
        _ = selectionViewModel.moveNext()
    }

    private func selectMedication(id medicationID: Medication.ID) {
        _ = selectionViewModel.selectMedication(id: medicationID)
    }

    private func selectMedication(at targetIndex: Int) {
        _ = selectionViewModel.selectMedication(at: targetIndex)
    }

    /// Only for selections made off-screen — a swipe is animated by the scroll itself.
    private var pageScrollAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.34, extraBounce: 0.02)
    }

    private var background: some View {
        MedicationDetailBackground(
            tint: selectionViewModel.selectedMedication.map { Color(hex: $0.bottleColorHex) }
        )
    }
}

struct MedicationDetailScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let medication: Medication
    let pageCount: Int
    let selectedIndex: Int?
    var onAddMedication: () -> Void
    var onManageMedications: () -> Void
    var onShowHistory: () -> Void
    var onRefill: (Medication) -> Void
    var onMovePrevious: () -> Void
    var onMoveNext: () -> Void

    @StateObject private var viewModel: MedicationDetailViewModel
    @State private var remainingHighlight = false
    @State private var doseFeedbackTrigger = 0
    @State private var manualDoseMedication: Medication?
    private let primaryColor = AppTheme.accent

    init(
        medication: Medication,
        store: MedicationStore,
        pageCount: Int,
        selectedIndex: Int?,
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
                VStack(spacing: 12) {
                    if pageCount > 1 {
                        MedicationPageIndicator(
                            pageCount: pageCount,
                            selectedIndex: selectedIndex ?? 0
                        )
                        .padding(.bottom, 2)
                    }

                    if let snapshot = viewModel.snapshot {
                        MedicationTodayCard(status: snapshot.todayStatus)

                        MedicationDetailHeroSection(
                            snapshot: snapshot,
                            sceneHeight: bottleSceneHeight(for: geometry)
                        )

                        MedicationStockCard(
                            status: snapshot.stockStatus,
                            tint: Color(hex: snapshot.hero.bottleColorHex),
                            tabletsPerDose: max(1, snapshot.medication.tabletsPerDose),
                            isHighlighted: remainingHighlight,
                            refillAction: {
                                onRefill(snapshot.medication)
                            }
                        )

                        RecentDoseRecordsCard(
                            records: snapshot.recentDoseRecords,
                            historyMetric: historyMetric(from: snapshot),
                            onShowHistory: onShowHistory,
                            onAddManualDose: {
                                manualDoseMedication = snapshot.medication
                            }
                        )
                    } else {
                        MedicationDetailLoadingCard()
                            .padding(.top, 36)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 84)
            }
            // The stack grows when the snapshot replaces the loading card; without this
            // the scroll view keeps its old offset and the verdict card starts hidden
            // under the toolbar.
            .defaultScrollAnchor(.top)
            .refreshable {
                await viewModel.refresh()
            }
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
                VStack(spacing: 8) {
                    if let undoableDose = viewModel.undoableDose {
                        DoseUndoBar(record: undoableDose) {
                            viewModel.undoLastDose()
                        }
                        .transition(undoTransition)
                    }

                    if let snapshot = viewModel.snapshot {
                        MedicationDetailActionBar(
                            actions: snapshot.actions,
                            isLoading: viewModel.isLoading,
                            primaryColor: primaryColor,
                            primaryAction: {
                                handlePrimaryAction(snapshot)
                            }
                        )
                    }
                }
                .animation(undoAnimation, value: viewModel.undoableDose?.id)
            }
            .onDisappear {
                viewModel.cancelUndo()
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
            .sheet(item: $manualDoseMedication) { medication in
                ManualDoseLogView(
                    medication: medication,
                    latestAllowedDate: viewModel.latestAllowedManualDoseDate
                ) { takenAt in
                    viewModel.logManualDose(takenAt: takenAt)
                }
            }
            .sensoryFeedback(.success, trigger: doseFeedbackTrigger)
        }
    }

    private var undoTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var undoAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.85)
    }

    private func historyMetric(from snapshot: MedicationDetailSnapshot) -> MedicationDetailMetric? {
        snapshot.metrics.first { $0.kind == .doseHistory }
    }

    /// The stage is now only as tall as the bottle it draws — the old height reserved
    /// 37% headroom for a hint that no longer exists, which read as a hole in the layout.
    private func bottleSceneHeight(for geometry: GeometryProxy) -> CGFloat {
        min(157, max(141, geometry.size.height * 0.18))
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

    private func handlePrimaryAction(_ snapshot: MedicationDetailSnapshot) {
        guard snapshot.actions.canLogDose else {
            onRefill(snapshot.medication)
            return
        }

        Task {
            await viewModel.logDose()

            guard viewModel.errorMessage == nil else { return }
            triggerDoseFeedback()
        }
    }

    private func triggerDoseFeedback() {
        doseFeedbackTrigger += 1

        withAnimation(feedbackAnimation) {
            remainingHighlight = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            withAnimation(feedbackAnimation) {
                remainingHighlight = false
            }
        }
    }

    private var feedbackAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.72)
    }
}

struct MedicationDetailBackground: View {
    let tint: Color?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            if let tint {
                LinearGradient(
                    colors: [
                        tint.opacity(0.20),
                        tint.opacity(0.07),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )

                LinearGradient(
                    colors: [
                        .clear,
                        tint.opacity(0.10)
                    ],
                    startPoint: .center,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
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
        .padding(.horizontal, 10)
        .frame(height: 28)
        .liquidGlassCapsuleSurface()
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
                systemImage: "list.bullet",
                label: "Manage medications",
                hint: "Opens medication management.",
                action: onManageMedications
            )
            ToolbarIconButton(
                systemImage: "plus",
                label: "Add medication",
                hint: "Opens the form to add another medication.",
                action: onAddMedication
            )
            ToolbarIconButton(
                systemImage: "calendar",
                label: "Dose history",
                hint: "Shows logged doses.",
                isPrimary: true,
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

struct LiquidGlassCapsuleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var tint: Color = AppTheme.accent
    /// `false` draws the outlined variant used once today's dose is already logged.
    var isProminent = true

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if isProminent {
            prominentBody(configuration: configuration)
        } else {
            outlinedBody(configuration: configuration)
        }
    }

    @ViewBuilder
    private func prominentBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            nativeGlassBody(configuration: configuration)
        } else {
            fallbackBody(configuration: configuration)
        }
    }

    @available(iOS 26.0, *)
    private func nativeGlassBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .contentShape(Capsule())
            .glassEffect(.regular.tint(tint.opacity(0.82)).interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.84), value: configuration.isPressed)
    }

    private func fallbackBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(tint, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.74), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }

    private func outlinedBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(AppTheme.surface, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.84), value: configuration.isPressed)
            .contentShape(Capsule())
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

    func liquidGlassCapsuleSurface() -> some View {
        modifier(LiquidGlassCapsuleSurfaceModifier())
    }
}

private struct LiquidGlassCapsuleSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content
                .glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(AppTheme.surface, in: Capsule())
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            heroText(alignment: .center, textAlignment: .center)
                .frame(maxWidth: 340, alignment: .center)
                .padding(.bottom, 12)

            bottleStage

            // At accessibility sizes the readout no longer fits beside the bottle, so
            // it drops below the stage rather than overlapping the glass.
            if dynamicTypeSize.isAccessibilitySize {
                supplyReadout
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private func heroText(
        alignment: HorizontalAlignment,
        textAlignment: TextAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: snapshot.hero.bottleColorHex))
                    .frame(width: 11, height: 11)

                Text(snapshot.hero.classificationText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .background(AppTheme.surfaceSubtle, in: Capsule())

            Text(snapshot.hero.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(textAlignment)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Purely a readout. It takes no taps, so a swipe that starts on the glass still
    /// pages to the next medication instead of being swallowed by the bottle.
    private func bottleScene(height: CGFloat) -> some View {
        MedicationBottleGauge(medication: snapshot.medication, height: height)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .allowsHitTesting(false)
            .accessibilityLabel("\(snapshot.hero.name) bottle")
    }

    /// The bottle now carries the number, so the readout sits at the stage's baseline
    /// beside it rather than in a card below.
    @ViewBuilder
    private var supplyReadout: some View {
        let status = snapshot.stockStatus

        VStack(alignment: .trailing, spacing: 0) {
            Text(status.daysRemaining.map(String.init) ?? "\(status.remainingCount)")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.primaryText)
                .contentTransition(.numericText())
                .lineLimit(1)

            Text(supplyUnitText)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)

            Text(status.supplyDetail.lowercasedSentence)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 124, alignment: .trailing)
        .padding(.bottom, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.supplyHeadline). \(status.supplyDetail).")
    }

    private var supplyUnitText: String {
        guard let daysRemaining = snapshot.stockStatus.daysRemaining else {
            return snapshot.stockStatus.remainingCount == 1 ? "tablet left" : "tablets left"
        }
        return daysRemaining == 1 ? "day left" : "days left"
    }

    private var bottleStage: some View {
        bottleScene(height: sceneHeight)
            .frame(maxWidth: 360, alignment: .center)
            .frame(height: sceneHeight, alignment: .center)
            .overlay(alignment: .bottomTrailing) {
                if !dynamicTypeSize.isAccessibilitySize {
                    supplyReadout
                        .padding(.trailing, 4)
                }
            }
    }
}

/// The screen's first answer: did I take this today? Kept free of any dependency
/// beyond `MedicationTodayStatus` so a Lock Screen widget can reuse it verbatim.
struct MedicationTodayCard: View {
    let status: MedicationTodayStatus

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: status.systemImage)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(glyphColor)
                .frame(width: 44, height: 44)
                .background(iconCircleFill, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                // The card is the screen's first answer, not a log: it stays two lines
                // tall no matter how many doses the day collected.
                Text(status.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !status.scheduleDetail.isEmpty {
                    Label(status.scheduleDetail, systemImage: "bell.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medicationCardSurface(
            tier,
            fill: cardFill,
            borderTint: accent,
            borderOpacity: borderOpacity
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
    }

    private var tier: MedicationCardTier {
        switch status.verdict {
        case .takenToday, .dueNow: .primary
        case .upcoming, .noSchedule: .tertiary
        }
    }

    private var accent: Color {
        switch status.verdict {
        case .takenToday: AppTheme.accent
        case .dueNow: AppTheme.warning
        case .upcoming, .noSchedule: AppTheme.accent
        }
    }

    private var cardFill: Color {
        switch status.verdict {
        case .takenToday: AppTheme.accent.opacity(0.10)
        case .dueNow: AppTheme.warning.opacity(0.10)
        case .upcoming, .noSchedule: AppTheme.surface
        }
    }

    private var borderOpacity: Double {
        switch status.verdict {
        case .takenToday: 0.24
        case .dueNow: 0.30
        case .upcoming, .noSchedule: 0
        }
    }

    private var iconCircleFill: Color {
        switch status.verdict {
        case .takenToday, .dueNow: accent
        case .upcoming, .noSchedule: AppTheme.accent.opacity(0.11)
        }
    }

    private var glyphColor: Color {
        switch status.verdict {
        case .takenToday, .dueNow: .white
        case .upcoming, .noSchedule: AppTheme.accent
        }
    }
}

/// Five-second reversal for the dose that was just logged.
private struct DoseUndoBar: View {
    let record: DoseRecord
    var undoAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Dose logged · \(record.takenAt.formatted(date: .omitted, time: .shortened))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: undoAction) {
                Text("Undo")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Removes the dose that was just logged and returns the tablets to the bottle.")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(minHeight: 46)
        .background(AppTheme.surfaceStrong, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 7, x: 0, y: 4)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement("Dose logged. Undo available.").post()
        }
    }
}

struct MedicationStockCard: View {
    let status: MedicationStockStatus
    let tint: Color
    var tabletsPerDose: Int = 1
    let isHighlighted: Bool
    var refillAction: () -> Void

    /// One row: the bottle above already carries the headline number.
    var body: some View {
        Button(action: refillAction) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(statusAccent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rowSummaryText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let secondaryText {
                        Text(secondaryText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(status.level == .ready ? AppTheme.secondaryText : statusAccent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                refillIndicator
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .medicationCardSurface(
                .secondary,
                borderTint: statusAccent,
                borderOpacity: isHighlighted ? 0.62 : borderOpacity,
                borderWidth: isHighlighted ? 2 : 1
            )
            .scaleEffect(isHighlighted ? 1.018 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens refill options for this medication.")
    }

    /// "30 tablets left" · the dose count, which only says something new when a dose is
    /// more than one tablet. The bottle above already carries the days-left number, so
    /// repeating supply here would waste the row.
    var rowSummaryText: String {
        let tablets = "\(status.remainingCount) \(tabletLabel) left"
        guard tabletsPerDose > 1 else { return tablets }

        let doses = status.remainingDoses
        return "\(tablets) · \(doses) \(doses == 1 ? "dose" : "doses") at \(tabletsPerDose) per dose"
    }

    /// When to act. A healthy bottle gets the day to reorder by; a low or empty one gets
    /// the urgency it already computed.
    var secondaryText: String? {
        guard status.level == .ready else { return messageText }
        guard let reorderByDate = status.reorderByDate else { return nil }

        return "Order by \(reorderByDate.formatted(.dateTime.month().day())) to avoid running out"
    }

    var titleText: String {
        status.title
    }

    var messageText: String {
        status.message
    }

    var tabletLabel: String {
        status.remainingCount == 1 ? "tablet" : "tablets"
    }

    var accessibilitySummary: String {
        "Remaining, \(status.remainingCount) \(tabletLabel). \(titleText). \(messageText)"
    }

    private var refillIndicator: some View {
        HStack(spacing: 5) {
            Text("Refill")
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .heavy))
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(statusAccent)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(minHeight: 26)
        .background(statusAccent.opacity(0.11), in: Capsule())
    }

    private var statusIcon: String {
        switch status.level {
        case .ready:
            return "checkmark.circle.fill"
        case .low:
            return "exclamationmark.circle.fill"
        case .empty:
            return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private var statusAccent: Color {
        switch status.level {
        case .ready:
            return tint
        case .low:
            return AppTheme.warning
        case .empty:
            return AppTheme.critical
        }
    }

    private var borderOpacity: Double {
        switch status.level {
        case .ready:
            return 0.22
        case .low:
            return 0.38
        case .empty:
            return 0.46
        }
    }
}

private struct RecentDoseRecordsCard: View {
    let records: [DoseRecord]
    let historyMetric: MedicationDetailMetric?
    var onShowHistory: () -> Void
    var onAddManualDose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dose History")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(historySummaryText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: onAddManualDose) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.accent, in: Circle())
                }
                .accessibilityLabel("Add missed dose")
                .accessibilityHint("Opens a form to record a dose taken earlier.")

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
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    let visibleRecords = Array(records.prefix(4))
                    ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                        RecentDoseTimelineRow(
                            record: record,
                            isFirst: index == 0,
                            isLast: index == visibleRecords.count - 1
                        )
                    }
                }
            }
        }
        .padding(14)
        .medicationCardSurface(.tertiary)
        .accessibilityElement(children: .contain)
    }

    private var historySummaryText: String {
        guard let historyMetric else {
            return records.isEmpty ? "No logged doses yet" : "\(records.count) recent doses"
        }

        if let subtitle = historyMetric.subtitle {
            return "\(historyMetric.value) \(subtitle)"
        }

        return "\(historyMetric.value) logged doses"
    }
}

private struct RecentDoseTimelineRow: View {
    let record: DoseRecord
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            timelineMarker
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(record.takenAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(record.takenAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFirst ? AppTheme.accent : AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("\(record.tabletCount) tablet\(record.tabletCount == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast ? 0 : 10)
        .accessibilityElement(children: .combine)
    }

    private var timelineMarker: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isFirst ? AppTheme.accent : AppTheme.accent.opacity(0.16))
                    .frame(width: 24, height: 24)

                Image(systemName: isFirst ? "checkmark" : "circle.fill")
                    .font(.system(size: isFirst ? 11 : 6, weight: .bold))
                    .foregroundStyle(isFirst ? .white : AppTheme.accent)
            }
            .accessibilityHidden(true)

            if !isLast {
                Rectangle()
                    .fill(AppTheme.separator)
                    .frame(width: 1, height: 28)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 24)
    }
}

private struct MedicationDetailActionBar: View {
    let actions: MedicationDetailActions
    let isLoading: Bool
    let primaryColor: Color
    var primaryAction: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    primaryButton
                }
            } else {
                primaryButton
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
            Label(actions.primaryTitle, systemImage: actions.primarySystemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(
            LiquidGlassCapsuleButtonStyle(
                tint: primaryColor,
                isProminent: !(actions.canLogDose && actions.isDoseLoggedToday)
            )
        )
        .disabled(isLoading)
        .accessibilityLabel(actions.primaryTitle)
        .accessibilityHint(actions.canLogDose ? "Logs the scheduled dose for this medication." : "Opens refill options for this medication.")
    }

}

private struct MedicationDetailLoadingCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.accent)

            Text("Loading medication details")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160)
        .medicationCardSurface(.secondary, borderOpacity: 0)
    }
}

struct StatPill: View {
    let title: String
    let value: String
    private let titleColor = AppTheme.secondaryText

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(titleColor)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 62)
        .medicationCardSurface(.tertiary)
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    private let titleColor = AppTheme.secondaryText

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(titleColor)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 62)
        .medicationCardSurface(.tertiary)
    }
}

struct RefillInfoCard: View {
    let accentColor: Color
    private let titleColor = AppTheme.secondaryText

    var body: some View {
        VStack(spacing: 3) {
            Text("Bottle")
                .font(.caption.weight(.medium))
                .foregroundStyle(titleColor)

            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .bold))
                Text("Refill")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(accentColor)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 62)
        .medicationCardSurface(.tertiary, borderTint: accentColor, borderOpacity: 0.36)
    }
}

struct EmptyMedicationView: View {
    let hasDoseHistory: Bool
    var addAction: () -> Void
    var historyAction: () -> Void

    /// An empty amber bottle — this is the one screen where showing the product sells it.
    private var emptyBottle: Medication {
        Medication(
            id: UUID(),
            name: "",
            tabletsRemaining: 0,
            tabletsPerDose: 1,
            bottleColorHex: AppTheme.bottleColors[0],
            lastTakenAt: nil,
            bottleCapacity: 30
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            BottleSceneView(medication: emptyBottle, isInteractive: false)
                .frame(height: 180)
                .frame(maxWidth: 260)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Add your first bottle")
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Track what's left, and never guess whether you've taken today's dose.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: addAction) {
                Label("Add Medication", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(LiquidGlassCapsuleButtonStyle(tint: AppTheme.accent))
            .accessibilityHint("Opens the form to add your first medication.")

            if hasDoseHistory {
                Button(action: historyAction) {
                    Label("View Dose History", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("View preserved dose history")
                .accessibilityHint("Opens dose history from medications that may no longer be active.")
            }

            Spacer()
        }
        .frame(maxWidth: 420)
    }
}
