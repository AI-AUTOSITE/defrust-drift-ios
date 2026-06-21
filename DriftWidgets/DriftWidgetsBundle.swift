//
//  DriftWidgetsBundle.swift
//  DriftWidgetsExtension
//
//  Widget bundle entry point (@main). Drift ships a single summary widget for
//  launch — Home Screen S/M/L plus Lock Screen inline/rectangular/circular,
//  all defined in DriftWidgets.swift. Future widgets (e.g. a single-subscription
//  widget) are added to this bundle's body.
//

import SwiftUI
import WidgetKit

@main
struct DriftWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DriftSummaryWidget()
    }
}
