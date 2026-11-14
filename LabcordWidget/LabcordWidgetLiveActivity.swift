//
//  LabcordWidgetLiveActivity.swift
//  LabcordWidget
//
//  Created by 정홍섭 on 11/14/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LabcordWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct LabcordWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LabcordWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension LabcordWidgetAttributes {
    fileprivate static var preview: LabcordWidgetAttributes {
        LabcordWidgetAttributes(name: "World")
    }
}

extension LabcordWidgetAttributes.ContentState {
    fileprivate static var smiley: LabcordWidgetAttributes.ContentState {
        LabcordWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: LabcordWidgetAttributes.ContentState {
         LabcordWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: LabcordWidgetAttributes.preview) {
   LabcordWidgetLiveActivity()
} contentStates: {
    LabcordWidgetAttributes.ContentState.smiley
    LabcordWidgetAttributes.ContentState.starEyes
}
