//
//  Views/Settings/HelpFAQView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/21.
//

import SwiftUI

struct HelpFAQView: View {
    var body: some View {
        List {
            Section("はじめに") {
                Text("KaKeBo は、10秒で支出を記録し、月末の振り返りをラクにする家計簿アプリです。まずはカテゴリを整え、＋ボタンから日々の記録を追加しましょう。")
            }
            Section("よくある質問") {
                FAQRow(q: "カテゴリは後から変更できますか？",
                       a: "はい。設定 → カテゴリ管理から編集・並べ替え・削除が可能です。")
                FAQRow(q: "毎月の固定費を自動で計上できますか？",
                       a: "設定 → 固定費 でテンプレートを作成すると、当月の期日に自動計上されます。")
                FAQRow(q: "リマインダーの時間を変えたい",
                       a: "設定 → リマインダーを管理 から、複数ルールの作成や曜日/条件のカスタムが行えます。")
                FAQRow(q: "ウィジェットの反映が遅い",
                       a: "データ保存後は自動で更新指示を出していますが、iOSの都合で遅延することがあります。しばらく待ってから確認してください。")
                FAQRow(q: "共有リンクを開いても参加できない",
                       a: "LINEなどのアプリ内ブラウザでは参加画面が開かないことがあります。リンクを長押しでコピーし、Safariで貼り付けて開いてください。")
                FAQRow(q: "共有リンクを開くとWebページだけ表示される",
                       a: "アプリ未インストール時やアプリ内ブラウザ利用時に起きることがあります。アプリを入れたあと、Safariで同じリンクを開くと参加に進めます。")
            }
            Section("困ったときは") {
                Text("設定画面の『バグ報告・アプリへのご意見』からメールでご連絡ください。ログやスクリーンショットがあると解決が早くなります。")
            }
        }
        .listStyle(.insetGrouped)
        .listRowBackground(FlatListRowBackground())
    }
}

private struct FAQRow: View {
    let q: String
    let a: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Q. \(q)").font(.subheadline.weight(.semibold))
            Text(a).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
