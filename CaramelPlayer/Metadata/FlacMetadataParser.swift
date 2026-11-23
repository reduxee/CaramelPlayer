import Foundation

/// FLAC 元数据手动解析器
///
/// 背景：AVFoundation（macOS 13）能正常「播放」FLAC，但对 FLAC 的 Vorbis Comment
/// 标签（TITLE/ARTIST/ALBUM/LYRICS）与内嵌封面（PICTURE block）暴露不完整。
/// 因此这里直接按 FLAC 规范解析文件头部的 metadata block：
///
/// - Block 类型 4 = VORBIS_COMMENT：字段为 "KEY=value"（UTF-8），长度为小端序
/// - Block 类型 6 = PICTURE：含 MIME / 描述 / 图片二进制数据（小端序长度字段）
///
/// 【内嵌歌词重点】FLAC 的同步歌词通常写在 Vorbis Comment 的
/// LYRICS / UNSYNCEDLYRICS / SYNCEDLYRICS 字段中，内容本身就是 LRC 文本。
enum FlacMetadataParser {

    struct FlacInfo {
        var tags: [String: String] = [:]      // key 统一为大写
        var pictureData: Data? = nil          // 内嵌专辑封面
    }

    enum ParseError: Error {
        case notFlac                  // 不是 "fLaC" 文件头
        case truncated                // 文件被截断 / 损坏
    }

    /// 解析 FLAC 文件的元数据（标签 + 封面）。
    /// 只顺序读取头部 metadata block，遇到 AUDIO block 即停止，大文件也能快速返回。
    static func parse(url: URL) throws -> FlacInfo {
        guard let data = try? Data(contentsOf: url, options: [.alwaysMapped]) else {
            throw ParseError.truncated
        }
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> FlacInfo {
        var info = FlacInfo()

        // 1. 校验 "fLaC" 魔数
        guard data.count >= 4, data.prefix(4) == Data("fLaC".utf8) else {
            throw ParseError.notFlac
        }

        var offset = 4
        var isLastBlock = false
        // 2. 遍历 metadata block，最多防御性循环 128 次（正常 FLAC < 10 个 block）
        var guardCounter = 0
        while !isLastBlock, guardCounter < 128 {
            guardCounter += 1
            guard offset + 4 <= data.count else { throw ParseError.truncated }

            // block header：1 字节（最高位 = 是否最后一个 block，低 7 位 = 类型）+ 3 字节大端长度
            let header = data[data.startIndex + offset]
            isLastBlock = (header & 0x80) != 0
            let blockType = Int(header & 0x7F)
            let blockLength = Int(data[data.startIndex + offset + 1]) << 16
                | Int(data[data.startIndex + offset + 2]) << 8
                | Int(data[data.startIndex + offset + 3])
            offset += 4

            guard offset + blockLength <= data.count else { throw ParseError.truncated }
            let blockData = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + blockLength))
            offset += blockLength

            switch blockType {
            case 4: // VORBIS_COMMENT
                if let tags = parseVorbisComment(blockData) {
                    for (k, v) in tags { info.tags[k.uppercased()] = v }
                }
            case 6: // PICTURE（内嵌专辑封面）
                if info.pictureData == nil, let pic = parsePicture(blockData) {
                    info.pictureData = pic
                }
            default:
                break // 其他 block（SEEKTABLE 等）与本播放器无关，跳过
            }
        }
        return info
    }

    // MARK: - VORBIS_COMMENT block 解析（内嵌歌词 / 歌名 / 歌手 / 专辑都在这里）

    /// Vorbis Comment 结构（全部小端序）：
    /// [vendor 长度 u32][vendor][评论数 u32]{ [长度 u32][KEY=value] × N }
    private static func parseVorbisComment(_ data: Data) -> [String: String]? {
        var offset = data.startIndex
        var dict: [String: String] = [:]

        // vendor 字符串（规范规定必须有，读取后弃用）
        guard let vendorLen = readLE32(data, &offset) else { return nil }
        guard data.distance(from: offset, to: data.endIndex) >= vendorLen else { return nil }
        offset = data.index(offset, offsetBy: vendorLen)

        guard let commentCount = readLE32(data, &offset) else { return nil }

        for _ in 0..<min(commentCount, 4096) { // 防御：异常大的评论数按上限截断
            guard let len = readLE32(data, &offset),
                  data.distance(from: offset, to: data.endIndex) >= len else { break }
            let bytes = data.subdata(in: offset..<data.index(offset, offsetBy: len))
            offset = data.index(offset, offsetBy: len)

            guard let entry = String(data: bytes, encoding: .utf8),
                  let eq = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[entry.startIndex..<eq])
            let value = String(entry[entry.index(after: eq)...])
            if !key.isEmpty, !value.isEmpty {
                dict[key] = value
            }
        }
        return dict.isEmpty ? nil : dict
    }

    // MARK: - PICTURE block 解析（内嵌封面）

    /// PICTURE 结构（全大端）：
    /// [类型 u32][MIME 长度 u32][MIME][描述长度 u32][描述][宽 u32][高 u32][色深 u32][颜色数 u32]
    /// [图片数据长度 u32][图片数据]
    private static func parsePicture(_ data: Data) -> Data? {
        var offset = data.startIndex
        guard readBE32(data, &offset) != nil else { return nil }        // picture type（弃用）
        guard let mimeLen = readBE32(data, &offset),
              data.distance(from: offset, to: data.endIndex) >= mimeLen else { return nil }
        offset = data.index(offset, offsetBy: mimeLen)                  // MIME（弃用）
        guard let descLen = readBE32(data, &offset),
              data.distance(from: offset, to: data.endIndex) >= descLen else { return nil }
        offset = data.index(offset, offsetBy: descLen)                  // 描述（弃用）
        offset = data.index(offset, offsetBy: 16)                       // 宽/高/色深/颜色数 共 16 字节
        guard let picLen = readBE32(data, &offset),
              picLen > 0,
              data.distance(from: offset, to: data.endIndex) >= picLen else { return nil }
        let pic = data.subdata(in: offset..<data.index(offset, offsetBy: picLen))
        // 只接受常见图片格式，避免把异常数据当封面
        let isImage = pic.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])        // PNG
            || pic.prefix(3) == Data([0xFF, 0xD8, 0xFF])                     // JPEG
            || pic.count > 12 && pic.prefix(4) == Data("RIFF".utf8)          // WEBP
        return isImage ? pic : nil
    }

    // MARK: - 小工具：定长整数读取（注意 FLAC 混用大端 / 小端）

    private static func readLE32(_ data: Data, _ offset: inout Data.Index) -> Int? {
        guard data.distance(from: offset, to: data.endIndex) >= 4 else { return nil }
        let v = Int(data[offset])
            | Int(data[data.index(after: offset)]) << 8
            | Int(data[data.index(offset, offsetBy: 2)]) << 16
            | Int(data[data.index(offset, offsetBy: 3)]) << 24
        offset = data.index(offset, offsetBy: 4)
        return v < 0 ? v + 0x100000000 : v   // 防御异常负值（读取错误数据时）
    }

    private static func readBE32(_ data: Data, _ offset: inout Data.Index) -> Int? {
        guard data.distance(from: offset, to: data.endIndex) >= 4 else { return nil }
        let v = Int(data[offset]) << 24
            | Int(data[data.index(after: offset)]) << 16
            | Int(data[data.index(offset, offsetBy: 2)]) << 8
            | Int(data[data.index(offset, offsetBy: 3)])
        offset = data.index(offset, offsetBy: 4)
        return v < 0 ? v + 0x100000000 : v
    }
}
