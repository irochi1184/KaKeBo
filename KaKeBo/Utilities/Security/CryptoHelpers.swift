//
//  Utilities/Security/CryptoHelpers.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/03.
//

import Foundation
import CryptoKit

enum CryptoHelpers {
    static func sha256(_ data: Data) -> Data {
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }
    
    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess)
        return Data(bytes)
    }
    
    static func base32(_ data: Data) -> String {
        // 簡易Base32（復旧コード表示用）。短くしたいので5bitごと。
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // 似た文字除外
        var out = ""
        var buffer: UInt64 = 0
        var bits: Int = 0
        for b in data {
            buffer = (buffer << 8) | UInt64(b)
            bits += 8
            while bits >= 5 {
                let idx = Int((buffer >> UInt64(bits - 5)) & 0x1F)
                out.append(alphabet[idx])
                bits -= 5
            }
        }
        if bits > 0 {
            let idx = Int((buffer << UInt64(5 - bits)) & 0x1F)
            out.append(alphabet[idx])
        }
        return stride(from: 0, to: out.count, by: 4).map {
            let s = out.index(out.startIndex, offsetBy: $0)
            let e = out.index(s, offsetBy: min(4, out.distance(from: s, to: out.endIndex)))
            return String(out[s..<e])
        }.joined(separator: "-")
    }
}
