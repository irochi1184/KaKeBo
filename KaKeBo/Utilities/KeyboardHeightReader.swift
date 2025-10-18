//
//  KeyboardHeightReader.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/18.
//

import SwiftUI
import Combine
import UIKit

final class KeyboardHeightReader: ObservableObject {
    @Published var height: CGFloat = 0
    
    private var chToken: NSObjectProtocol?
    private var hideToken: NSObjectProtocol?
    
    init() {
        // --- 修正版 ---
        chToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main,
            using: { [weak self] note in   // ← ← ← using: を明示
                guard
                    let self,
                    let window = UIApplication.shared.connectedScenes
                        .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
                    let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return }
                
                let kbInWin = window.convert(frame, from: nil)
                let overlap = max(0, window.bounds.maxY - kbInWin.minY)
                self.height = overlap
            }
        )
        
        hideToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                self?.height = 0
            }
        )
    }
    
    deinit {
        if let t = chToken { NotificationCenter.default.removeObserver(t) }
        if let t = hideToken { NotificationCenter.default.removeObserver(t) }
    }
}
