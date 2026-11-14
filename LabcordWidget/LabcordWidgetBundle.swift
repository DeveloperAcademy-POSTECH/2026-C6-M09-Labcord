//
//  LabcordWidgetBundle.swift
//  LabcordWidget
//
//  Created by 정홍섭 on 11/14/26.
//

import WidgetKit
import SwiftUI

@main
struct LabcordWidgetBundle: WidgetBundle {
    var body: some Widget {
        LabcordWidget()
        LabcordWidgetLiveActivity()
    }
}
