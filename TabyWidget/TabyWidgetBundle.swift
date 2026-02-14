//
//  TabyWidgetBundle.swift
//  TabyWidget
//

import SwiftUI
import WidgetKit

@main
struct TabyWidgetBundle: WidgetBundle {
    var body: some Widget {
        IncompleteTodosWidget()
        LatestMessageWidget()
    }
}
