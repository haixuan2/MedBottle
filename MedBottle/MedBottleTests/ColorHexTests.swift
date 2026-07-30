import SwiftUI
import XCTest
@testable import MedBottle

/// The bottle color picker writes `Color.hexString` into `Medication.bottleColorHex`,
/// and every consumer reads it back through `Color(hex:)` / `UIColor(hex:)`.
/// These tests pin that round trip so a saved swatch always renders as the color the
/// user picked.
final class ColorHexTests: XCTestCase {
    /// The swatches offered in `AddMedicationView` and `ManageMedicationsView`.
    private let paletteHexes = ["D99A00", "C87B00", "8FB7D8", "74A88D", "D35F7B"]

    func testUIColorParsesHexIntoExpectedComponents() {
        let expectations: [(hex: String, red: Int, green: Int, blue: Int)] = [
            ("000000", 0, 0, 0),
            ("FFFFFF", 255, 255, 255),
            ("FF0000", 255, 0, 0),
            ("00FF00", 0, 255, 0),
            ("0000FF", 0, 0, 255),
            ("D99A00", 217, 154, 0)
        ]

        for expectation in expectations {
            let color = UIColor(hex: expectation.hex)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(
                color.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
                "\(expectation.hex) should produce an RGB-compatible color"
            )

            XCTAssertEqual(red * 255, CGFloat(expectation.red), accuracy: 0.5, "red for \(expectation.hex)")
            XCTAssertEqual(green * 255, CGFloat(expectation.green), accuracy: 0.5, "green for \(expectation.hex)")
            XCTAssertEqual(blue * 255, CGFloat(expectation.blue), accuracy: 0.5, "blue for \(expectation.hex)")
            XCTAssertEqual(alpha, 1, accuracy: 0.001, "alpha for \(expectation.hex)")
        }
    }

    func testPaletteSwatchesSurviveHexRoundTrip() {
        for hex in paletteHexes {
            XCTAssertEqual(
                UIColor(hex: hex).hexString,
                hex,
                "palette swatch \(hex) should round trip unchanged"
            )
        }
    }

    /// `hexString` truncates rather than rounds when converting components back to
    /// bytes, so sweep every channel value to prove no swatch can drift by one step.
    func testEveryChannelValueSurvivesHexRoundTrip() {
        for byte in 0...255 {
            let hex = String(format: "%02X%02X%02X", byte, byte, byte)
            XCTAssertEqual(UIColor(hex: hex).hexString, hex, "gray level \(byte) should round trip")

            let redOnly = String(format: "%02X0000", byte)
            XCTAssertEqual(UIColor(hex: redOnly).hexString, redOnly, "red level \(byte) should round trip")
        }
    }

    func testColorAndUIColorAgreeOnTheSameHex() {
        for hex in paletteHexes {
            XCTAssertEqual(
                Color(hex: hex).hexString,
                UIColor(hex: hex).hexString,
                "Color and UIColor should decode \(hex) identically"
            )
        }
    }

    /// The picker hands back a SwiftUI `Color`; this is the exact path a saved
    /// custom color takes from `ColorPicker` to storage and back. Repeat the cycle so a
    /// per-save drift of a single step cannot hide behind a one-shot assertion.
    func testColorDoesNotDriftAcrossRepeatedSaves() {
        for hex in paletteHexes {
            var stored = hex
            for cycle in 1...10 {
                stored = Color(hex: stored).hexString
                XCTAssertEqual(
                    stored,
                    hex,
                    "custom color \(hex) drifted to \(stored) after \(cycle) save cycle(s)"
                )
            }
        }
    }

    func testHexStringIsUppercaseSixDigits() {
        for hex in paletteHexes {
            let produced = UIColor(hex: hex).hexString
            XCTAssertEqual(produced.count, 6, "\(produced) should be six digits")
            XCTAssertEqual(produced, produced.uppercased(), "\(produced) should be uppercase")
        }
    }
}
