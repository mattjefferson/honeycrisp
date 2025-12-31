import Foundation
import zlib

enum NoteDataDecoder {
    static func decodeNoteText(from data: Data) throws -> String? {
        let unzipped = try gunzip(data)
        return decodeTopLevel(from: unzipped)
    }

    private static func decodeTopLevel(from data: Data) -> String? {
        var reader = ProtobufReader(data: data)
        while let tag = reader.readTag() {
            if tag.wireType == .lengthDelimited {
                let length = try? reader.readLength()
                if let length {
                    let subdata = try? reader.readBytes(count: length)
                    if let subdata {
                        if tag.fieldNumber == 3, let text = decodeNoteMessage(from: subdata) {
                            return text
                        }
                        if tag.fieldNumber == 2, let text = decodeEnvelope(from: subdata) {
                            return text
                        }
                    }
                }
            }
            try? reader.skip(wireType: tag.wireType)
        }
        return nil
    }

    private static func decodeEnvelope(from data: Data) -> String? {
        var reader = ProtobufReader(data: data)
        while let tag = reader.readTag() {
            if tag.fieldNumber == 3, tag.wireType == .lengthDelimited {
                let length = try? reader.readLength()
                if let length, let subdata = try? reader.readBytes(count: length) {
                    if let text = decodeNoteMessage(from: subdata) {
                        return text
                    }
                }
            } else {
                try? reader.skip(wireType: tag.wireType)
            }
        }
        return nil
    }

    private static func decodeNoteMessage(from data: Data) -> String? {
        var reader = ProtobufReader(data: data)
        while let tag = reader.readTag() {
            if tag.fieldNumber == 2, tag.wireType == .lengthDelimited {
                let length = try? reader.readLength()
                if let length {
                    return try? reader.readString(count: length)
                }
                return nil
            } else {
                try? reader.skip(wireType: tag.wireType)
            }
        }
        return nil
    }

    private static func gunzip(_ data: Data) throws -> Data {
        if data.isEmpty { return data }

        return try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Data()
            }

            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: baseAddress)
            stream.avail_in = uInt(rawBuffer.count)

            var status = inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            if status != Z_OK {
                throw CLIError(message: "Failed to initialize gzip decoder")
            }

            var output = Data()
            let chunkSize = 64 * 1024
            var buffer = [UInt8](repeating: 0, count: chunkSize)

            repeat {
                var produced = 0
                do {
                    try buffer.withUnsafeMutableBytes { rawBuffer in
                        guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                            throw CLIError(message: "Failed to allocate gzip output buffer")
                        }
                        stream.next_out = baseAddress
                        stream.avail_out = uInt(chunkSize)

                        status = inflate(&stream, Z_SYNC_FLUSH)
                        produced = chunkSize - Int(stream.avail_out)
                    }
                } catch {
                    inflateEnd(&stream)
                    throw error
                }

                if status == Z_STREAM_ERROR || status == Z_DATA_ERROR || status == Z_MEM_ERROR {
                    inflateEnd(&stream)
                    throw CLIError(message: "Failed to decode gzip data")
                }

                if produced > 0 {
                    output.append(buffer, count: produced)
                }
            } while status != Z_STREAM_END

            inflateEnd(&stream)
            return output
        }
    }
}

enum WireType: UInt8 {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

struct ProtobufReader {
    let data: Data
    var index: Int = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readTag() -> (fieldNumber: Int, wireType: WireType)? {
        if index >= data.count { return nil }
        guard let raw = try? readVarint() else { return nil }
        let wire = WireType(rawValue: UInt8(raw & 0x7))
        let fieldNumber = Int(raw >> 3)
        guard let wire else { return nil }
        return (fieldNumber, wire)
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.count {
            let byte = data[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift > 63 {
                throw CLIError(message: "Invalid protobuf varint")
            }
        }
        throw CLIError(message: "Unexpected EOF while reading varint")
    }

    mutating func readLength() throws -> Int {
        let length = try readVarint()
        guard length <= UInt64(Int.max) else {
            throw CLIError(message: "Invalid protobuf length")
        }
        return Int(length)
    }

    mutating func readBytes(count: Int) throws -> Data {
        guard index + count <= data.count else {
            throw CLIError(message: "Unexpected EOF while reading bytes")
        }
        let sub = data[index..<(index + count)]
        index += count
        return Data(sub)
    }

    mutating func readString(count: Int) throws -> String {
        let bytes = try readBytes(count: count)
        return String(data: bytes, encoding: .utf8) ?? ""
    }

    mutating func skip(wireType: WireType) throws {
        switch wireType {
        case .varint:
            _ = try readVarint()
        case .fixed64:
            index += 8
        case .fixed32:
            index += 4
        case .lengthDelimited:
            let length = try readLength()
            index += length
        }
    }
}
