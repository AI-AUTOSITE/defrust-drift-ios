//
//  HexColorTests.swift
//  DriftTests
//
//  Verifies the pure hex parser behind `Color(hex:)`. Color itself is hard to
//  assert on (no component-wise equality without a trait environment), so the
//  parsing is split into `HexColor.rgb(from:)` returning a `DriftRGB`, and we
//  test that.
//

@testable import Drift
import Foundation
import Testing

@Suite("Hex color parsing")
@MainActor
struct HexColorTests {

    @Test("Parses a #RRGGBB string")
    func parsesWithHash() {
        let rgb = HexColor.rgb(from: "#5E5CE6")
        #expect(rgb == DriftRGB(
            red: Double(0x5E) / 255,
            green: Double(0x5C) / 255,
            blue: Double(0xE6) / 255
        ))
    }

    @Test("Parses a bare RRGGBB string (no leading hash)")
    func parsesWithoutHash() {
        #expect(HexColor.rgb(from: "5E5CE6") == HexColor.rgb(from: "#5E5CE6"))
    }

    @Test("Black and white map to the 0 and 1 bounds exactly")
    func parsesBounds() {
        #expect(HexColor.rgb(from: "#000000") == DriftRGB(red: 0, green: 0, blue: 0))
        #expect(HexColor.rgb(from: "#FFFFFF") == DriftRGB(red: 1, green: 1, blue: 1))
    }

    @Test("Invalid strings return nil")
    func rejectsInvalid() {
        #expect(HexColor.rgb(from: "") == nil)
        #expect(HexColor.rgb(from: "xyz") == nil)
        #expect(HexColor.rgb(from: "#FFF") == nil)       // 3-digit shorthand unsupported
        #expect(HexColor.rgb(from: "#12345G") == nil)    // 'G' is not a hex digit
    }
}
