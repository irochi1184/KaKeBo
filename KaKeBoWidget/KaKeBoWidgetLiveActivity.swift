//
//  KaKeBoWidgetLiveActivity.swift
//  KaKeBoWidget
//
//  Created by 有田健一郎 on 2025/10/16.
//
// ライブアクティビティは継続的な進行状況向け（例：タイマー、配達）。
// 家計簿で使うなら「今月の予算消化率を常時表示」「本日の支出“記録セッション”」など。
// すぐは不要ならコメントアウトでOK。

//import ActivityKit
//import WidgetKit
//import SwiftUI
//
//struct KaKeBoWidgetAttributes: ActivityAttributes {
//    public struct ContentState: Codable, Hashable {
//        // Dynamic stateful properties about your activity go here!
//        var emoji: String
//    }
//
//    // Fixed non-changing properties about your activity go here!
//    var name: String
//}
//
//struct KaKeBoWidgetLiveActivity: Widget {
//    var body: some WidgetConfiguration {
//        ActivityConfiguration(for: KaKeBoWidgetAttributes.self) { context in
//            // Lock screen/banner UI goes here
//            VStack {
//                Text("Hello \(context.state.emoji)")
//            }
//            .activityBackgroundTint(Color.cyan)
//            .activitySystemActionForegroundColor(Color.black)
//
//        } dynamicIsland: { context in
//            DynamicIsland {
//                // Expanded UI goes here.  Compose the expanded UI through
//                // various regions, like leading/trailing/center/bottom
//                DynamicIslandExpandedRegion(.leading) {
//                    Text("Leading")
//                }
//                DynamicIslandExpandedRegion(.trailing) {
//                    Text("Trailing")
//                }
//                DynamicIslandExpandedRegion(.bottom) {
//                    Text("Bottom \(context.state.emoji)")
//                    // more content
//                }
//            } compactLeading: {
//                Text("L")
//            } compactTrailing: {
//                Text("T \(context.state.emoji)")
//            } minimal: {
//                Text(context.state.emoji)
//            }
//            .widgetURL(URL(string: "http://www.apple.com"))
//            .keylineTint(Color.red)
//        }
//    }
//}
//
//extension KaKeBoWidgetAttributes {
//    fileprivate static var preview: KaKeBoWidgetAttributes {
//        KaKeBoWidgetAttributes(name: "World")
//    }
//}
//
//extension KaKeBoWidgetAttributes.ContentState {
//    fileprivate static var smiley: KaKeBoWidgetAttributes.ContentState {
//        KaKeBoWidgetAttributes.ContentState(emoji: "😀")
//     }
//     
//     fileprivate static var starEyes: KaKeBoWidgetAttributes.ContentState {
//         KaKeBoWidgetAttributes.ContentState(emoji: "🤩")
//     }
//}
//
//#Preview("Notification", as: .content, using: KaKeBoWidgetAttributes.preview) {
//   KaKeBoWidgetLiveActivity()
//} contentStates: {
//    KaKeBoWidgetAttributes.ContentState.smiley
//    KaKeBoWidgetAttributes.ContentState.starEyes
//}
