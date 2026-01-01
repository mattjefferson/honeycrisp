import XCTest
@testable import honeycrisp
import zlib

final class HoneycrispTests: XCTestCase {
    func testParseArgsParsesFlagsOptionsAndPositionals() {
        let args = [
            "--json",
            "--limit", "10",
            "--account=Personal",
            "--folder", "Work",
            "-m",
            "title",
            "--",
            "--literal",
            "-x"
        ]

        let parsed = Honeycrisp.parseArgs(args)

        XCTAssertTrue(parsed.flags.contains("--json"))
        XCTAssertTrue(parsed.flags.contains("--markdown"))
        XCTAssertEqual(parsed.options["--limit"], "10")
        XCTAssertEqual(parsed.options["--account"], "Personal")
        XCTAssertEqual(parsed.options["--folder"], "Work")
        XCTAssertEqual(parsed.positionals, ["title", "--literal", "-x"])
    }

    func testParseNoteSummariesSkipsMalformedLines() {
        let output = "id1\tFirst\ninvalid\nid2\tSecond\n"
        let parsed = Honeycrisp.parseNoteSummaries(output)

        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].id, "id1")
        XCTAssertEqual(parsed[0].title, "First")
        XCTAssertEqual(parsed[1].id, "id2")
        XCTAssertEqual(parsed[1].title, "Second")
    }

    func testExtractTagsFindsUniqueTags() {
        let text = "Hello #One #two #one\n#Two and #three"
        let tags = Honeycrisp.extractTags(from: text)
        XCTAssertEqual(tags, ["One", "two", "three"])
    }

    func testNormalizeBulletLineConvertsBullets() {
        XCTAssertEqual(Honeycrisp.normalizeBulletLine("• item"), "[ ] item")
        XCTAssertEqual(Honeycrisp.normalizeBulletLine("\t\t• item"), "    [ ] item")
        XCTAssertNil(Honeycrisp.normalizeBulletLine("- not a bullet"))
    }

    func testNormalizePlainTextLists() {
        let text = "• one\n\t• two\nplain"
        let normalized = Honeycrisp.normalizePlainTextLists(text)
        XCTAssertEqual(normalized, "[ ] one\n  [ ] two\nplain")
    }

    func testRenderChecklistPlainTextConvertsLinesAfterTitle() {
        let text = "Snowbird List\nCPAP\nFirestick"
        let rendered = Honeycrisp.renderChecklistPlainText(text, title: "Snowbird List")
        XCTAssertEqual(rendered, "Snowbird List\n[ ] CPAP\n[ ] Firestick")
    }

    func testHtmlLooksLikeChecklistDetectsLists() {
        let listHTML = "<ul><li>One</li><li>Two</li></ul>"
        let paragraphHTML = "<p>Just text</p>"

        XCTAssertTrue(Honeycrisp.htmlLooksLikeChecklist(listHTML))
        XCTAssertFalse(Honeycrisp.htmlLooksLikeChecklist(paragraphHTML))
    }

    func testAppendChecklistItemHTMLAddsListItem() {
        let html = "<ul><li>First</li></ul>"
        let updated = Honeycrisp.appendChecklistItemHTML(html, item: "Second")
        XCTAssertNotNil(updated)
        XCTAssertTrue(updated?.contains("First") == true)
        XCTAssertTrue(updated?.contains("Second") == true)
    }

    func testAsAppleScriptStringExprHandlesNewlines() {
        XCTAssertEqual(AppleScriptWriter.asAppleScriptStringExpr("hello"), "\"hello\"")
        XCTAssertEqual(AppleScriptWriter.asAppleScriptStringExpr("a\nb"), "\"a\" & linefeed & \"b\"")
    }

    func testParseCoreDataIDExtractsPrimaryKey() {
        let coreData = "x-coredata://0A0B0C0D-EEEE-FFFF-1111-222233334444/Note/p123"
        XCTAssertEqual(Honeycrisp.parseCoreDataID(coreData), 123)
        XCTAssertNil(Honeycrisp.parseCoreDataID("not-coredata"))
    }

    func testDecodeNoteTextHandlesLegacyEnvelope() throws {
        let payload = makeLegacyNotePayload(text: "Legacy note body")
        let gzipData = try gzip(payload)
        let decoded = try NoteDataDecoder.decodeNoteText(from: gzipData)
        XCTAssertEqual(decoded, "Legacy note body")
    }

    func testDecodeNoteTextHandlesModernEnvelope() throws {
        let payload = makeModernNotePayload(text: "Modern note body")
        let gzipData = try gzip(payload)
        let decoded = try NoteDataDecoder.decodeNoteText(from: gzipData)
        XCTAssertEqual(decoded, "Modern note body")
    }
}

private enum GzipError: Error {
    case initFailed
    case encodeFailed
}

private func gzip(_ data: Data) throws -> Data {
    if data.isEmpty { return data }

    var stream = z_stream()
    var status = deflateInit2_(
        &stream,
        Z_DEFAULT_COMPRESSION,
        Z_DEFLATED,
        16 + MAX_WBITS,
        8,
        Z_DEFAULT_STRATEGY,
        ZLIB_VERSION,
        Int32(MemoryLayout<z_stream>.size)
    )
    guard status == Z_OK else { throw GzipError.initFailed }

    var output = Data()
    let chunkSize = 64 * 1024
    var buffer = [UInt8](repeating: 0, count: chunkSize)

    data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return }
        stream.next_in = UnsafeMutablePointer(mutating: baseAddress)
        stream.avail_in = uInt(rawBuffer.count)

        repeat {
            buffer.withUnsafeMutableBytes { rawBuffer in
                guard let outBase = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return }
                stream.next_out = outBase
                stream.avail_out = uInt(chunkSize)
                status = deflate(&stream, Z_FINISH)
            }

            let produced = chunkSize - Int(stream.avail_out)
            if produced > 0 {
                output.append(buffer, count: produced)
            }
        } while status == Z_OK
    }

    deflateEnd(&stream)
    guard status == Z_STREAM_END else { throw GzipError.encodeFailed }
    return output
}

private func makeLegacyNotePayload(text: String) -> Data {
    let noteMessage = makeNoteMessage(text: text)
    return makeLengthDelimitedField(number: 3, payload: noteMessage)
}

private func makeModernNotePayload(text: String) -> Data {
    let noteMessage = makeNoteMessage(text: text)
    var envelope = Data()
    envelope.append(makeVarintField(number: 1, value: 0))
    envelope.append(makeVarintField(number: 2, value: 0))
    envelope.append(makeLengthDelimitedField(number: 3, payload: noteMessage))

    var topLevel = Data()
    topLevel.append(makeVarintField(number: 1, value: 0))
    topLevel.append(makeLengthDelimitedField(number: 2, payload: envelope))
    return topLevel
}

private func makeNoteMessage(text: String) -> Data {
    let payload = Data(text.utf8)
    return makeLengthDelimitedField(number: 2, payload: payload)
}

private func makeVarintField(number: Int, value: UInt64) -> Data {
    var data = Data()
    data.append(makeVarint(UInt64((number << 3) | 0)))
    data.append(makeVarint(value))
    return data
}

private func makeLengthDelimitedField(number: Int, payload: Data) -> Data {
    var data = Data()
    data.append(makeVarint(UInt64((number << 3) | 2)))
    data.append(makeVarint(UInt64(payload.count)))
    data.append(payload)
    return data
}

private func makeVarint(_ value: UInt64) -> Data {
    var value = value
    var bytes: [UInt8] = []
    while true {
        var byte = UInt8(value & 0x7f)
        value >>= 7
        if value != 0 {
            byte |= 0x80
        }
        bytes.append(byte)
        if value == 0 { break }
    }
    return Data(bytes)
}
