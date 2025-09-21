import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house.fill") }
            CategoryListView()
                .tabItem { Label("カテゴリ", systemImage: "square.grid.2x2.fill") }
            ReportsView()
                .tabItem { Label("レポート", systemImage: "chart.pie.fill") }
        }
    }
}