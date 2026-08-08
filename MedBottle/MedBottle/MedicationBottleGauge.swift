import SwiftUI

/// A flat, straight-on bottle whose fill level *is* the supply reading.
///
/// The SceneKit bottle communicates in discrete pill bodies capped at 18, so 30 and 24
/// tablets look identical. A continuous fill reads as a gauge at a glance, at any size,
/// and costs no physics. Every dimension derives from `height`, so the hero stage and a
/// 36pt list thumbnail share one implementation.
struct MedicationBottleGauge: View {
    let medication: Medication
    /// Full stage height; every part is derived from this so the gauge works
    /// at hero size and at peek size from one implementation.
    let height: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            groundShadow

            VStack(spacing: 0) {
                cap
                neckBand
                bottleBody
            }
        }
        // Bottom-aligned in the stage: the bottle rests on the ground its shadow implies,
        // and its base lines up with the supply readout at the stage baseline. The bottle
        // fills the stage now — the only slack is the sliver the ground shadow needs.
        .frame(width: max(capWidth, bodyWidth * 1.25), height: height, alignment: .bottom)
        .animation(fillAnimation, value: fillRatio)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(medication.name) bottle")
        .accessibilityValue("\(medication.tabletsRemaining) of \(medication.bottleCapacity) tablets")
    }

    // MARK: - Geometry

    private var capWidth: CGFloat { height * 0.473 }
    private var capHeight: CGFloat { height * 0.134 }
    private var neckWidth: CGFloat { height * 0.435 }
    private var neckHeight: CGFloat { height * 0.054 }
    private var bodyWidth: CGFloat { height * 0.606 }
    private var bodyHeight: CGFloat { height * 0.763 }

    /// cap + neck + body. The bottle claims all but ~5% of the stage; that remainder is
    /// the ground shadow's room, not layout headroom.
    static func bottleHeight(inStageOf height: CGFloat) -> CGFloat {
        height * (0.134 + 0.054 + 0.763)
    }

    private var fillRatio: Double { medication.fillRatio }

    private var fillHeight: CGFloat {
        Self.fillHeight(bodyHeight: bodyHeight, fillRatio: fillRatio)
    }

    /// Fill height in points, with the three clamps the design calls for: nothing at
    /// empty, a 6pt floor so a bottle holding tablets never reads as empty, and a 4pt
    /// ceiling so the meniscus stays visible below the shoulder.
    static func fillHeight(bodyHeight: CGFloat, fillRatio: Double) -> CGFloat {
        guard fillRatio > 0, bodyHeight > 0 else { return 0 }

        let maximum = max(0, bodyHeight - 4)
        let minimum = min(6, maximum)
        return min(max(bodyHeight * fillRatio, minimum), maximum)
    }

    private var bodyShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: height * 0.048,
            bottomLeadingRadius: height * 0.092,
            bottomTrailingRadius: height * 0.092,
            topTrailingRadius: height * 0.048,
            style: .continuous
        )
    }

    // MARK: - Parts

    private var groundShadow: some View {
        Ellipse()
            .fill(isDark ? Color.black.opacity(0.45) : AppTheme.primaryText.opacity(0.22))
            .frame(width: bodyWidth * 1.25, height: height * 0.054)
            .blur(radius: height * 0.045)
            .offset(y: height * 0.027)
            .accessibilityHidden(true)
    }

    private var cap: some View {
        capShape
            .fill(capGradient)
            .overlay {
                capRidges
                    .clipShape(capShape)
            }
            .frame(width: capWidth, height: capHeight)
            .shadow(color: .black.opacity(0.14), radius: height * 0.027, x: 0, y: height * 0.012)
    }

    private var capShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: height * 0.036,
            bottomLeadingRadius: height * 0.018,
            bottomTrailingRadius: height * 0.018,
            topTrailingRadius: height * 0.036,
            style: .continuous
        )
    }

    /// Drawn rather than imaged so the ridge pitch stays constant at every gauge size.
    private var capRidges: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                context.fill(
                    Path(CGRect(x: x, y: 0, width: 1.5, height: size.height)),
                    with: .color(.black.opacity(0.07))
                )
                x += 5
            }
        }
    }

    private var neckBand: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 2,
            bottomTrailingRadius: 2,
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(
            LinearGradient(
                colors: [tint.opacity(0.90), tint.mix(with: .black, by: 0.2).opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(width: neckWidth, height: neckHeight)
    }

    private var bottleBody: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(glassGradient)

            if fillHeight > 0 {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(fillGradient)

                    // The meniscus is what makes the level legible; without it the
                    // fill and the glass blur together at small sizes.
                    if fillRatio > 0.02 {
                        Rectangle()
                            .fill(Color.white.opacity(isDark ? 0.42 : 0.55))
                            .frame(height: 2)
                    }
                }
                .frame(height: fillHeight)
            }

            cylinderShading
            specularStripe
            emptyLabel
        }
        .frame(width: bodyWidth, height: bodyHeight)
        .clipShape(bodyShape)
        .overlay {
            bodyShape
                .strokeBorder(tint.mix(with: .black, by: 0.35).opacity(0.30), lineWidth: 1)
        }
    }

    /// A darkened right edge is what sells a cylinder on a flat shape.
    private var cylinderShading: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.16)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: bodyWidth * 0.22)
        }
        .allowsHitTesting(false)
    }

    private var specularStripe: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: bodyWidth * 0.06, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isDark
                            ? [Color.white.opacity(0.34), Color.white.opacity(0.04)]
                            : [Color.white.opacity(0.50), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: bodyWidth * 0.12, height: bodyHeight * 0.78)
                .blur(radius: 2)
                .blendMode(.plusLighter)
            Spacer(minLength: 0)
        }
        .padding(.top, bodyHeight * 0.06)
        .frame(width: bodyWidth, alignment: .leading)
        .padding(.leading, bodyWidth * 0.10)
        .allowsHitTesting(false)
    }

    /// Drawn whenever it actually fits rather than above a guessed size threshold, so it
    /// survives Dynamic Type at hero size and drops out cleanly in a list thumbnail.
    /// The level, the readout beside the gauge and the accessibility value all carry the
    /// same fact, so losing the word costs nothing.
    @ViewBuilder
    private var emptyLabel: some View {
        if fillRatio <= 0 {
            ViewThatFits {
                Text("Empty")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize()

                Color.clear
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Values

    private var tint: Color { Color(hex: medication.bottleColorHex) }

    private var isDark: Bool { colorScheme == .dark }

    private var glassBaseAlpha: Double { isDark ? 0.42 : 0.50 }

    private var capGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color(hex: "E4E9E7"), Color(hex: "9BA6A2")]
                : [Color(hex: "FDFDFC"), Color(hex: "D9DEDC")],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Empty glass. Approximates the reference's 100° sweep with a shallow diagonal.
    private var glassGradient: LinearGradient {
        let base = fillRatio <= 0 ? glassBaseAlpha * 0.8 : glassBaseAlpha

        return LinearGradient(
            stops: [
                .init(color: tint.opacity(base), location: 0),
                .init(color: tint.mix(with: .black, by: 0.3).opacity(base * 0.84), location: 0.5),
                .init(color: tint.opacity(base * 1.1), location: 1)
            ],
            startPoint: UnitPoint(x: 0, y: 0.15),
            endPoint: UnitPoint(x: 1, y: 0.85)
        )
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [
                tint.opacity(0.98),
                tint.mix(with: .black, by: 0.28).opacity(0.92)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var fillAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }
}

#Preview("Bottle gauge — fill levels") {
    func medication(_ remaining: Int, _ hex: String) -> Medication {
        Medication(
            id: UUID(),
            name: "Finasteride",
            tabletsRemaining: remaining,
            tabletsPerDose: 1,
            bottleColorHex: hex,
            lastTakenAt: nil,
            bottleCapacity: 30
        )
    }

    return VStack(spacing: 24) {
        HStack(spacing: 8) {
            ForEach([30, 24, 15, 1, 0], id: \.self) { remaining in
                MedicationBottleGauge(medication: medication(remaining, "D99A00"), height: 200)
            }
        }

        HStack(spacing: 8) {
            ForEach(AppTheme.bottleColors, id: \.self) { hex in
                MedicationBottleGauge(medication: medication(18, hex), height: 140)
            }
        }
    }
    .padding()
    .background(
        LinearGradient(
            colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    )
}
