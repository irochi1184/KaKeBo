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
        "basket", "basket.fill",             // 買い物かご
        "bag", "bag.fill",                   // 袋
        "creditcard", "creditcard.fill",     // クレジット
        "wallet.pass", "wallet.pass.fill",   // 財布・支払い
        "banknote", "banknote.fill",         // 現金
        "takeoutbag.and.cup.and.straw", "takeoutbag.and.cup.and.straw.fill", // テイクアウト
        "cup.and.saucer", "cup.and.saucer.fill", // カフェ・飲み物
        "fork.knife", "fork.knife.circle", "fork.knife.circle.fill", // 食事
        "wineglass", "wineglass.fill",       // お酒
        "birthday.cake", "birthday.cake.fill", // 記念日
        "leaf", "leaf.fill",                 // エコ・自然
        "pawprint", "pawprint.fill",         // ペット
        "gift", "gift.fill",                 // ギフト
        "theatermasks", "theatermasks.fill", // エンタメ
        "music.note", "music.mic", "music.note.list", // 音楽
        "tv", "tv.fill",                     // 映画・TV
        "gamecontroller", "gamecontroller.fill", // ゲーム
        "graduationcap", "graduationcap.fill", // 教育・学習
        "book", "book.fill", "books.vertical", "books.vertical.fill", // 本
        "pencil", "pencil.circle", "pencil.circle.fill", // 文具
        "camera", "camera.fill", "photo", "photo.fill", "photo.on.rectangle", // 写真・カメラ
        "paintbrush", "paintbrush.fill", "paintbrush.pointed", "paintbrush.pointed.fill", // アート
        "hammer", "hammer.fill", "wrench", "wrench.fill", "wrench.and.screwdriver", "wrench.and.screwdriver.fill", // メンテ
        "scissors", "scissors.circle", "scissors.circle.fill", // 美容・手芸
        "tshirt", "tshirt.fill",             // 被服
        "tag", "tag.fill", "tag.circle", "tag.circle.fill", // タグ
        "barcode.viewfinder", "qrcode", "qrcode.viewfinder", // スキャン
        "calendar", "calendar.circle", "calendar.circle.fill", "calendar.badge.clock", // カレンダー
        "clock", "clock.fill", "alarm", "alarm.fill", "timer", "timer.square", "timer.square.fill", // 時間
        "envelope", "envelope.fill", "paperplane", "paperplane.fill", "phone", "phone.fill", // 通信
        "person", "person.fill", "person.2", "person.2.fill", "person.3", "person.3.fill", // 人
        "house", "house.fill", "house.circle", "house.circle.fill", // 住宅
        "building.2", "building.2.fill", "building.columns", "building.columns.fill", // 建物・役所
        "doc.text", "doc.text.fill", "doc.plaintext", // 書類
        "tray", "tray.fill", "archivebox", "archivebox.fill", // 収納
        "trash", "trash.fill",               // ごみ・廃棄
        "sparkles", "sparkles.tv", "sparkles.tv.fill", // サブスク・配信
        "cart.badge.plus", "cart.badge.minus", // 購入・返品
        "shippingbox", "shippingbox.fill",   // 配送
        "ticket", "ticket.fill",             // チケット
        "leaf.circle", "leaf.circle.fill",   // 自然

        // =========================
        // 電気・インフラ関連（白抜き/黒塗り混在）
        // =========================
        "bolt", "bolt.fill", "bolt.circle", "bolt.circle.fill",
        "bolt.slash", "bolt.slash.fill", "bolt.square", "bolt.square.fill",
        "battery.0", "battery.25", "battery.50", "battery.75", "battery.100",
        "battery.0.circle", "battery.100.circle", "battery.100.bolt", "battery.100.bolt.fill",
        "powerplug", "powerplug.fill", "powerplug.portrait", "powerplug.portrait.fill",
        "lightbulb", "lightbulb.fill", "lightbulb.slash", "lightbulb.slash.fill",
        "flashlight.off.fill", "flashlight.on.fill",
        "fan", "fan.fill",
        "wifi", "wifi.circle", "wifi.circle.fill", "wifi.slash",
        "antenna.radiowaves.left.and.right", "antenna.radiowaves.left.and.right.circle", "antenna.radiowaves.left.and.right.circle.fill",
        "car", "car.fill",
        "bus", "bus.fill", "tram", "tram.fill", "bicycle",
        "fuelpump", "fuelpump.fill",
        "stethoscope", "cross", "cross.circle", "cross.circle.fill",
        "bandage", "bandage.fill",
        "drop", "drop.fill", "drop.circle", "drop.circle.fill",
        "snowflake", "snowflake.circle", "snowflake.circle.fill",
        "sun.max", "sun.max.fill", "sun.min", "sun.min.fill",
        "cloud", "cloud.fill", "cloud.rain", "cloud.rain.fill", "cloud.bolt", "cloud.bolt.fill",

        // =========================
        // 交通・移動・旅行
        // =========================
        "airplane", "airplane.circle", "airplane.circle.fill",
        "car.2", "car.2.fill", "car.circle", "car.circle.fill",
        "bicycle.circle", "bicycle.circle.fill",
        "ferry", "ferry.fill",
        "bed.double", "bed.double.fill",
        "suitcase", "suitcase.fill",
        "map", "map.fill", "mappin", "mappin.circle", "mappin.circle.fill",
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
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                    }
                }
                .padding()
            }
        }
    }
}
