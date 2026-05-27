//
//  Views/LedgerLoadingView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/12/02.
//

import SwiftUI

struct LedgerLoadingView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var appear = false
    
    private var imageName: String {
        scheme == .dark ? "LoadingPhoto_dark" : "LoadingPhoto"
    }
    
    var body: some View {
        ZStack {
            // フォールバック背景色（画像リソース未発見時の白画面防止）
            Color(uiColor: scheme == .dark ? .systemBackground : .systemBackground)
                .ignoresSafeArea()

            // ① 背景画像：常にフルスクリーン中央
            Image(imageName)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .opacity(appear ? 1.0 : 0.0)
                .animation(.easeIn(duration: 0.35), value: appear)
            
            // ② ローディング表示：GeometryReader で位置だけ決める
            GeometryReader { proxy in
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    
                    Text("家計簿を準備しています…")
                        .font(.footnote)
                        .foregroundStyle(.primary.opacity(0.8))
                }
                // 画面の「中央より少し下」に固定
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height * 0.62   // ここを 0.58〜0.65 くらいで微調整してOK
                )
                .opacity(appear ? 1.0 : 0.0)
                .animation(.easeIn(duration: 0.35).delay(0.1), value: appear)
            }
            .ignoresSafeArea() // notch やホームバー含めて高さベースで位置計算
        }
        .onAppear {
            appear = true
        }
    }
}

#Preview("Loading Light") {
    LedgerLoadingView()
        .preferredColorScheme(.light)
}

#Preview("Loading Dark") {
    LedgerLoadingView()
        .preferredColorScheme(.dark)
}
