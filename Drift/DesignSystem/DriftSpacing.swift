//
//  DriftSpacing.swift
//  Drift
//
//  Spacing and corner-radius scales (points). Use these tokens instead of
//  raw literals so padding and rounding stay consistent across screens.
//  Short names (`s4`, `.m`, `.l`) are intentional design-token shorthand;
//  the project disables SwiftLint's identifier_name rule.
//

import SwiftUI

enum DriftSpacing {
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s40: CGFloat = 40
    static let s56: CGFloat = 56
    static let s80: CGFloat = 80
}

enum DriftRadius {
    static let xs: CGFloat = 6
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let pill: CGFloat = 999
}
