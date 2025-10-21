//
//  Utilities/ActivityView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/21.
//

import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems,
                                 applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) { }
}
