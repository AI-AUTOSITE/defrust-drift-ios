//
//  DriftTests.swift
//  DriftTests
//
//  Created by Hidekazu Yamaoka on 2026/06/11.
//

import Testing
@testable import Drift

struct DriftTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

}

/// The free-tier gate is pure arithmetic, so it runs everywhere (including CI) —
/// no StoreKit session or simulator account required. The boundary (the 10th add
/// is allowed, the 11th is not) is the bit most likely to go wrong, so it is
/// pinned here.
@Suite("DriftStore — free tier gate")
struct FreeTierGateTests {

    @Test("Free tier allows up to the limit, blocks beyond it")
    func freeTierBoundary() {
        #expect(DriftStore.canAdd(currentCount: 0, isPro: false) == true)
        #expect(DriftStore.canAdd(currentCount: 9, isPro: false) == true)   // adding the 10th
        #expect(DriftStore.canAdd(currentCount: 10, isPro: false) == false) // 11th is blocked
        #expect(DriftStore.canAdd(currentCount: 11, isPro: false) == false)
    }

    @Test("Pro is never capped")
    func proUnlimited() {
        #expect(DriftStore.canAdd(currentCount: 10, isPro: true) == true)
        #expect(DriftStore.canAdd(currentCount: 999, isPro: true) == true)
    }

    @Test("Free tier limit is ten")
    func freeTierLimitValue() {
        #expect(DriftStore.freeTierLimit == 10)
    }
}
