//
//  Views/Security/PasscodePad.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/03.
//

import SwiftUI

struct PasscodeDots: View {
    let length: Int
    let filled: Int
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<length, id: \.self) { i in
                Circle()
                    .fill(i < filled ? Color.primary : Color.secondary.opacity(0.25))
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("桁数 \(filled) / \(length)")
    }
}

struct NumericKeyButton: View {
    let label: String
    let subtitle: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label).font(.system(size: 28, weight: .regular, design: .default))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PasscodePad: View {
    /// 現在の入力（0-9 のみ）
    @Binding var input: String
    /// 目標の桁数（4 または 6 を想定）
    let digits: Int
    /// 入力完了時に呼ばれる
    let onComplete: (String) -> Void
    /// バイオメトリボタンを右下に出すか
    var showBiometrics: Bool = false
    var onBiometrics: (() -> Void)?
    
    private func push(_ d: String) {
        guard input.count < digits else { return }
        input.append(d)
        if input.count == digits {
            // 入力完了を少し遅らせてタップのエフェクト等を感じられるように
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                onComplete(input)
            }
        }
    }
    
    private func pop() {
        guard !input.isEmpty else { return }
        input.removeLast()
    }
    
    var body: some View {
        VStack(spacing: 14) {
            // 1 2 3
            HStack(spacing: 14) {
                NumericKeyButton(label: "1", subtitle: nil) { push("1") }
                NumericKeyButton(label: "2", subtitle: "ABC") { push("2") }
                NumericKeyButton(label: "3", subtitle: "DEF") { push("3") }
            }
            .frame(height: 56)
            
            // 4 5 6
            HStack(spacing: 14) {
                NumericKeyButton(label: "4", subtitle: "GHI") { push("4") }
                NumericKeyButton(label: "5", subtitle: "JKL") { push("5") }
                NumericKeyButton(label: "6", subtitle: "MNO") { push("6") }
            }
            .frame(height: 56)
            
            // 7 8 9
            HStack(spacing: 14) {
                NumericKeyButton(label: "7", subtitle: "PQRS") { push("7") }
                NumericKeyButton(label: "8", subtitle: "TUV") { push("8") }
                NumericKeyButton(label: "9", subtitle: "WXYZ") { push("9") }
            }
            .frame(height: 56)
            
            // 生体/空白 0 削除
            HStack(spacing: 14) {
                if showBiometrics, let onBiometrics {
                    Button(action: onBiometrics) {
                        Image(systemName: "faceid")
                            .font(.system(size: 24, weight: .regular))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.buttonStyle(.plain)
                } else {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                NumericKeyButton(label: "0", subtitle: nil) { push("0") }
                
                Button(action: pop) {
                    Image(systemName: "delete.left")
                        .font(.system(size: 22, weight: .regular))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain)
            }
            .frame(height: 56)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .buttonStyle(.plain)
    }
}
