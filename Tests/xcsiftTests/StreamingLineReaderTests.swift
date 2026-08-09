import Foundation
import XCTest
import XCSiftCore

@testable import xcsift

final class StreamingLineReaderTests: XCTestCase {
    func testEmitsCompleteLinesBeforeReadingTheNextChunk() throws {
        let log = EventLog()
        var source = ChunkSource(
            chunks: [
                Data("App.swift:4:2: war".utf8),
                Data("ning: unused value\n** BUILD SUC".utf8),
                Data("CEEDED **".utf8),
            ],
            log: log
        )
        var lines: [String] = []
        var reader = StreamingLineReader(chunkSize: 64)

        let scan = try reader.consume(from: &source) { line in
            log.entries.append("line:\(line)")
            lines.append(line)
        }

        XCTAssertEqual(
            lines,
            [
                "App.swift:4:2: warning: unused value",
                "** BUILD SUCCEEDED **",
            ]
        )
        XCTAssertEqual(
            log.entries,
            [
                "read:0",
                "read:1",
                "line:App.swift:4:2: warning: unused value",
                "read:2",
                "read:3",
                "line:** BUILD SUCCEEDED **",
            ]
        )
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testPOSIXSourceReadsPipedInput() throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data("first line\nsecond line".utf8))
        try pipe.fileHandleForWriting.close()
        var source = POSIXInputSource(
            fileDescriptor: pipe.fileHandleForReading.fileDescriptor
        )
        var reader = StreamingLineReader(chunkSize: 4)
        var lines: [String] = []

        let scan = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["first line", "second line"])
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testOversizedLineRetainsBoundedPrefixBeforeDiscardingItsTail() throws {
        var source = ChunkSource(
            chunks: [
                Data(repeating: 0x41, count: 100),
                Data("\n** BUILD SUCCEEDED **".utf8),
            ],
            log: EventLog()
        )
        var reader = StreamingLineReader(chunkSize: 128, maximumLineBytes: 32)
        var lines: [String] = []

        let scan = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, [String(repeating: "A", count: 32), "** BUILD SUCCEEDED **"])
        XCTAssertEqual(scan.oversizedLinesTruncated, 1)
        XCTAssertLessThanOrEqual(scan.maximumBufferedBytes, 32)
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testRepeatedOversizedChunksKeepReaderBufferBounded() throws {
        let oversizedChunks = Array(repeating: Data(repeating: 0x41, count: 4_096), count: 256)
        var source = ChunkSource(
            chunks: oversizedChunks + [Data("\nnext".utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader(chunkSize: 4_096)
        var lines: [FramedInputLine] = []

        let scan = try reader.consumeFramed(from: &source) { lines.append($0) }

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text.utf8.count, LineParser.maximumLineBytes)
        XCTAssertTrue(lines[0].isTruncated)
        XCTAssertEqual(lines[1].text, "next")
        XCTAssertFalse(lines[1].isTruncated)
        XCTAssertEqual(scan.oversizedLinesTruncated, 1)
        XCTAssertLessThanOrEqual(scan.maximumBufferedBytes, LineParser.maximumLineBytes)
    }

    func testPreservesUTF8ScalarsSplitAcrossSingleByteChunks() throws {
        let input = "警告🙂\n"
        var source = ChunkSource(
            chunks: input.utf8.map { Data([$0]) },
            log: EventLog()
        )
        var reader = StreamingLineReader(chunkSize: 1)
        var lines: [String] = []

        let scan = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["警告🙂", ""])
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testTruncatedUTF8PrefixIsValidAndFollowingLineRecovers() throws {
        var source = ChunkSource(
            chunks: "Command: 🙂🙂🙂\nnext\n".utf8.map { Data([$0]) },
            log: EventLog()
        )
        var reader = StreamingLineReader(chunkSize: 1, maximumLineBytes: 12)
        var lines: [FramedInputLine] = []

        let scan = try reader.consumeFramed(from: &source) { lines.append($0) }

        XCTAssertEqual(lines.map(\.text), ["Command: ", "next", ""])
        XCTAssertEqual(lines.map(\.isTruncated), [true, false, false])
        XCTAssertTrue(lines.allSatisfy { $0.text.utf8.count <= 12 })
        XCTAssertEqual(scan.oversizedLinesTruncated, 1)
        XCTAssertLessThanOrEqual(scan.maximumBufferedBytes, 12)
    }

    func testCombiningMarkTruncationMatchesCoreFraming() throws {
        let physicalLine = "Command: e" + String(repeating: "\u{301}", count: 32)
        let expected = FramedInputLine(physicalLine, maximumBytes: 16)
        var source = ChunkSource(
            chunks: [Data((physicalLine + "\n").utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader(chunkSize: 128, maximumLineBytes: 16)
        var lines: [FramedInputLine] = []

        _ = try reader.consumeFramed(from: &source) { lines.append($0) }

        XCTAssertEqual(lines.first?.text, expected.text)
        XCTAssertEqual(lines.first?.isTruncated, expected.isTruncated)
        XCTAssertLessThanOrEqual(lines.first?.text.utf8.count ?? .max, 16)
    }

    func testOversizedFlutterCommandMatchesCompleteInputParser() throws {
        let phase =
            "PhaseScriptExecution Run\\ Flutter /tmp/Script.sh (in target 'App' from project 'App')"
        let command =
            "  Command: /usr/bin/flutter --token reader-secret "
            + String(repeating: "--verbose-segment ", count: 500)
        let input = [
            phase,
            "ProcessException: No such file or directory",
            command,
            "Command PhaseScriptExecution failed with a nonzero exit code",
            "** BUILD FAILED **",
        ].joined(separator: "\n")
        var source = ChunkSource(
            chunks: stride(from: 0, to: input.utf8.count, by: 257).map { offset in
                let start = input.utf8.index(input.utf8.startIndex, offsetBy: offset)
                let end = input.utf8.index(start, offsetBy: min(257, input.utf8.count - offset))
                return Data(input.utf8[start ..< end])
            },
            log: EventLog()
        )
        var reader = StreamingLineReader(chunkSize: 257)
        var streamingParser = StreamingOutputParser()

        let scan = try reader.consumeFramed(from: &source) { streamingParser.feed($0) }
        let streamed = streamingParser.finish()
        let complete = OutputParser().parse(input: input)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        XCTAssertEqual(try encoder.encode(streamed), try encoder.encode(complete))
        XCTAssertEqual(scan.oversizedLinesTruncated, 1)
        XCTAssertTrue(streamed.errors.first?.message.contains("/usr/bin/flutter") == true)
        XCTAssertTrue(streamed.errors.first?.message.contains("… [truncated]") == true)
        XCTAssertTrue(streamed.errors.first?.message.contains("<redacted>") == true)
        XCTAssertFalse(streamed.errors.first?.message.contains("reader-secret") == true)
        XCTAssertLessThanOrEqual(streamed.errors.first?.message.utf8.count ?? .max, 4_700)
    }

    func testPreservesEmptyLinesAndUnterminatedFinalLine() throws {
        var source = ChunkSource(
            chunks: [Data("\n\nlast line".utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader()
        var lines: [String] = []

        _ = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["", "", "last line"])
    }

    func testPreservesCarriageReturnsFromCRLFInput() throws {
        var source = ChunkSource(
            chunks: [Data("first\r\nsecond\r\n".utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader()
        var lines: [String] = []

        _ = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["first\r", "second\r", ""])
    }

    func testSingleChunkLinesPreserveBufferAndOversizeSemantics() throws {
        var source = ChunkSource(
            chunks: [Data("1234\n\n12345\né\n".utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader(chunkSize: 64, maximumLineBytes: 4)
        var lines: [String] = []

        let scan = try reader.consume(from: &source) { lines.append($0) }

        XCTAssertEqual(lines, ["1234", "", "1234", "é", ""])
        XCTAssertEqual(scan.oversizedLinesTruncated, 1)
        XCTAssertEqual(scan.maximumBufferedBytes, 4)
        XCTAssertTrue(scan.containsNonWhitespace)
    }

    func testUnicodeWhitespaceDoesNotCountAsInputContent() throws {
        var source = ChunkSource(
            chunks: [Data("\u{2003}\n\t".utf8)],
            log: EventLog()
        )
        var reader = StreamingLineReader()

        let scan = try reader.consume(from: &source) { _ in }

        XCTAssertFalse(scan.containsNonWhitespace)
    }
}

private final class EventLog {
    var entries: [String] = []
}

private struct ChunkSource: InputChunkSource {
    let chunks: [Data]
    let log: EventLog
    private var index = 0

    init(chunks: [Data], log: EventLog) {
        self.chunks = chunks
        self.log = log
    }

    mutating func read(upToCount _: Int) throws -> Data? {
        log.entries.append("read:\(index)")
        defer { index += 1 }
        guard index < chunks.count else { return nil }
        return chunks[index]
    }
}
