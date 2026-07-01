//
//  Utilities/BackupArchive.swift
//  KaKeBo
//
//  外部ライブラリなしで ZIP アーカイブを生成・展開する最小実装。
//  バックアップ（JSON + 写真ファイル）を1つの .kakebo ファイルにまとめるために使用する。
//
//  - 圧縮方式は STORED（無圧縮, method=0）のみ。写真は既に JPEG 圧縮済みで
//    追加圧縮の効果が薄いため、実装が単純で信頼性の高い STORED を採用。
//  - 生成した ZIP は標準的な ZIP 形式なので Finder/Windows でも展開可能。
//  - 展開は本アプリが生成した STORED 形式のみを対象とする（自前生成→自前展開）。
//

import Foundation

enum BackupArchive {

    struct Entry {
        let path: String   // 例: "backup.json", "Photos/xxxx.jpg"
        let data: Data
    }

    /// 先頭シグネチャ "PK\u{03}\u{04}" で ZIP かどうかを判定
    static func isZip(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[data.startIndex] == 0x50
            && data[data.startIndex + 1] == 0x4B
            && data[data.startIndex + 2] == 0x03
            && data[data.startIndex + 3] == 0x04
    }

    // MARK: - 生成

    static func create(_ entries: [Entry]) -> Data {
        var out = Data()
        var central = Data()
        var count: UInt16 = 0

        for e in entries {
            let nameBytes = Array(e.path.utf8)
            let crc = crc32(e.data)
            let size = UInt32(e.data.count)
            let localOffset = UInt32(out.count)

            // ローカルファイルヘッダ
            out.appendLE32(0x04034b50)
            out.appendLE16(20)                       // version needed
            out.appendLE16(0)                        // flags
            out.appendLE16(0)                        // method: STORED
            out.appendLE16(0)                        // mod time
            out.appendLE16(0)                        // mod date
            out.appendLE32(crc)
            out.appendLE32(size)                     // compressed size
            out.appendLE32(size)                     // uncompressed size
            out.appendLE16(UInt16(nameBytes.count))
            out.appendLE16(0)                        // extra length
            out.append(contentsOf: nameBytes)
            out.append(e.data)

            // 中央ディレクトリエントリ
            central.appendLE32(0x02014b50)
            central.appendLE16(20)                    // version made by
            central.appendLE16(20)                    // version needed
            central.appendLE16(0)                     // flags
            central.appendLE16(0)                     // method
            central.appendLE16(0)                     // mod time
            central.appendLE16(0)                     // mod date
            central.appendLE32(crc)
            central.appendLE32(size)
            central.appendLE32(size)
            central.appendLE16(UInt16(nameBytes.count))
            central.appendLE16(0)                     // extra length
            central.appendLE16(0)                     // comment length
            central.appendLE16(0)                     // disk number start
            central.appendLE16(0)                     // internal attrs
            central.appendLE32(0)                     // external attrs
            central.appendLE32(localOffset)
            central.append(contentsOf: nameBytes)

            count += 1
        }

        let cdOffset = UInt32(out.count)
        let cdSize = UInt32(central.count)
        out.append(central)

        // End of Central Directory
        out.appendLE32(0x06054b50)
        out.appendLE16(0)            // disk number
        out.appendLE16(0)            // cd start disk
        out.appendLE16(count)        // entries on this disk
        out.appendLE16(count)        // total entries
        out.appendLE32(cdSize)
        out.appendLE32(cdOffset)
        out.appendLE16(0)            // comment length

        return out
    }

    // MARK: - 展開

    /// 本アプリが生成した STORED 形式 ZIP を展開する。
    /// ローカルファイルヘッダを先頭から順に走査する（flags=0・STORED 前提）。
    static func extract(_ data: Data) -> [Entry] {
        let bytes = [UInt8](data)
        var entries: [Entry] = []
        var i = 0

        func le16(_ o: Int) -> Int { Int(bytes[o]) | (Int(bytes[o + 1]) << 8) }
        func le32(_ o: Int) -> Int {
            Int(bytes[o]) | (Int(bytes[o + 1]) << 8) | (Int(bytes[o + 2]) << 16) | (Int(bytes[o + 3]) << 24)
        }

        while i + 30 <= bytes.count {
            let sig = le32(i)
            guard sig == 0x04034b50 else { break } // 中央ディレクトリ等に到達したら終了

            let method = le16(i + 8)
            let compSize = le32(i + 18)
            let nameLen = le16(i + 26)
            let extraLen = le16(i + 28)

            let nameStart = i + 30
            let nameEnd = nameStart + nameLen
            guard nameEnd <= bytes.count else { break }
            let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)

            let dataStart = nameEnd + extraLen
            let dataEnd = dataStart + compSize
            guard dataEnd <= bytes.count else { break }

            // STORED のみ対応。ディレクトリ（末尾 "/"）はスキップ
            if method == 0 && !name.hasSuffix("/") {
                entries.append(Entry(path: name, data: Data(bytes[dataStart..<dataEnd])))
            }

            i = dataEnd
        }

        return entries
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in data {
            crc = crcTable[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - リトルエンディアン書き込みヘルパー

private extension Data {
    mutating func appendLE16(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }
    mutating func appendLE16(_ v: Int) { appendLE16(UInt16(v)) }

    mutating func appendLE32(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
}
