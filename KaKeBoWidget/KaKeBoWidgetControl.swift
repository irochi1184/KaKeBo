//
//  KaKeBoWidgetControl.swift
//  KaKeBoWidget
//
//  Created by 有田健一郎 on 2025/10/16.
//
// これは iOS 18の「コントロール」（コントロールセンターやロック画面）用のサンプル。
// 家計簿なら「特定カテゴリへ+¥1,000」のトグルや、“家計簿に記録”ボタンなどに応用可能。
// まずは不要ならコメントアウト推奨。使うと決めたら、StartTimerIntent を AddTransactionIntent に差し替え。
//

//import AppIntents
//import SwiftUI
//import WidgetKit
//
//struct KaKeBoWidgetControl: ControlWidget {
//    static let kind: String = "com.irochi.KaKeBoX.KaKeBoWidget"
//
//    var body: some ControlWidgetConfiguration {
//        AppIntentControlConfiguration(
//            kind: Self.kind,
//            provider: Provider()
//        ) { value in
//            ControlWidgetToggle(
//                "Start Timer",
//                isOn: value.isRunning,
//                action: StartTimerIntent(value.name)
//            ) { isRunning in
//                Label(isRunning ? "On" : "Off", systemImage: "timer")
//            }
//        }
//        .displayName("Timer")
//        .description("A an example control that runs a timer.")
//    }
//}
//
//extension KaKeBoWidgetControl {
//    struct Value {
//        var isRunning: Bool
//        var name: String
//    }
//
//    struct Provider: AppIntentControlValueProvider {
//        func previewValue(configuration: TimerConfiguration) -> Value {
//            KaKeBoWidgetControl.Value(isRunning: false, name: configuration.timerName)
//        }
//
//        func currentValue(configuration: TimerConfiguration) async throws -> Value {
//            let isRunning = true // Check if the timer is running
//            return KaKeBoWidgetControl.Value(isRunning: isRunning, name: configuration.timerName)
//        }
//    }
//}
//
//struct TimerConfiguration: ControlConfigurationIntent {
//    static let title: LocalizedStringResource = "Timer Name Configuration"
//
//    @Parameter(title: "Timer Name", default: "Timer")
//    var timerName: String
//}
//
//struct StartTimerIntent: SetValueIntent {
//    static let title: LocalizedStringResource = "Start a timer"
//
//    @Parameter(title: "Timer Name")
//    var name: String
//
//    @Parameter(title: "Timer is running")
//    var value: Bool
//
//    init() {}
//
//    init(_ name: String) {
//        self.name = name
//    }
//
//    func perform() async throws -> some IntentResult {
//        // Start the timer…
//        return .result()
//    }
//}
