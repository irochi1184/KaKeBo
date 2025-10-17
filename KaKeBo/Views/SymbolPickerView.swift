import SwiftUI

struct SymbolPickerView: View {
    @Binding var selected: String
    @State private var query: String = ""

    private let symbols: [String] = [
        // =========================
        // 初期カテゴリで使用中のアイコン（優先表示）
        // =========================
        "fork.knife",                 // 食費
        "bag.fill",                   // 日用品費
        "lightbulb.fill",             // 水道光熱費
        "tram.fill",                  // 交通費
        "wifi",                       // 通信料
        "house.fill",                 // 住宅費
        "cross.case.fill",            // 医療費
        "tshirt.fill",                // 被服費
        "gift.fill",                  // 交際費
        "gamecontroller.fill",        // 娯楽費
        "scissors",                   // 美容費
        "figure.2.and.child.holdinghands", // 子ども費
        "ellipsis.circle.fill",       // 雑費
        "sparkles",                   // 特別費
        "shield.checkerboard",        // 保険料
        "car.fill",                   // 車両費
        "book.fill",                  // 学費
        "yensign.circle",             // 税金
        "music.note.list",            // 習い事
        "banknote.fill",              // 小遣い
        "banknote",                   // 給与
        "yensign.circle.fill",        // その他収入
        
        // =========================
        // よく使う汎用アイコン（追加分）
        // =========================
        "cart", "cart.fill",                 // ショッピング
        "creditcard", "creditcard.fill",     // クレジット
        "wallet.pass.fill",                  // 財布・支払い
        "takeoutbag.and.cup.and.straw.fill", // テイクアウト
        "cup.and.saucer.fill",               // カフェ・飲み物
        "bicycle", "bus.fill",               // 交通関連
        "fuelpump.fill",                     // ガソリン代
        "figure.walk", "figure.run",         // 健康・運動
        "dumbbell.fill",                     // トレーニング
        "stethoscope",                       // 健康管理
        "heart", "heart.fill",               // 健康・愛
        "cross",                             // 医療関連
        "pawprint.fill",                     // ペット関連
        "leaf.fill",                         // エコ・自然
        "globe.asia.australia.fill",         // 海外・旅行
        "airplane",                          // 旅行・出張
        "bed.double.fill",                   // 宿泊
        "camera.fill", "photo.on.rectangle", // 写真・カメラ
        "paintbrush.pointed.fill",           // アート・デザイン
        "music.note", "music.mic",           // 音楽・ライブ
        "tv.fill",                           // 映画・TV
        "gamecontroller",                    // ゲーム
        "graduationcap.fill",                // 教育・学習
        "hammer.fill", "wrench.and.screwdriver.fill", // メンテナンス
        "gearshape.fill", "cpu.fill",        // 設定・PC
        "tag.fill", "barcode.viewfinder",    // 商品タグ・スキャン
        "calendar", "calendar.badge.clock",  // カレンダー関連
        "clock.fill", "alarm.fill",          // 時間・予定
        "envelope.fill", "paperplane.fill",  // 通信・連絡
        "person.2.fill", "person.3.fill",    // 家族・人
        "house",                             // 住宅
        "building.columns.fill",             // 税金・役所
        "doc.text.fill",                     // 書類・契約
        "trash.fill",                        // ごみ・廃棄
        "sparkles.tv.fill",                  // サブスク・配信
    ]

    var filtered: [String] {
        guard !query.isEmpty else { return symbols }
        return symbols.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("検索", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            selected = name
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: name)
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                selected == name ? Color.accentColor : Color.secondary.opacity(0.25),
                                                lineWidth: 1
                                            )
                                    )

                                Text(name.replacingOccurrences(of: ".fill", with: ""))
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
}
