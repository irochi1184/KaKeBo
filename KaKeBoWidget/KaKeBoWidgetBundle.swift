//
//  KaKeBoWidgetBundle.swift
//  KaKeBoWidget
//
//  Created by 有田健一郎 on 2025/10/16.
//
// 複数ウィジェットを束ねる起点。
// 「ControlWidget」「LiveActivity」を使わないなら、いったん外す or 後で使う前提で残す。

import WidgetKit
import SwiftUI

@main
struct KaKeBoWidgetBundle: WidgetBundle {
    var body: some Widget {
        KaKeBoWidget()
//        KaKeBoWidgetControl()
//        KaKeBoWidgetLiveActivity()
    }
}
