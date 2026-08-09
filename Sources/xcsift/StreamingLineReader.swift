import Foundation
import XCSiftCore
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

protocol InputChunkSource {
    mutating func read(upToCount count: Int) throws -> Data?
}

struct POSIXInputSource: InputChunkSource {
    let fileDescriptor: Int32

    mutating func read(upToCount count: Int) throws -> Data? {
        var data = Data(count: count)

        while true {
            let bytesRead = data.withUnsafeMutableBytes { buffer in
                #if canImport(Darwin)
                    Darwin.read(fileDescriptor, buffer.baseAddress, count)
                #elseif canImport(Glibc)
                    Glibc.read(fileDescriptor, buffer.baseAddress, count)
                #elseif canImport(Musl)
                    Musl.read(fileDescriptor, buffer.baseAddress, count)
                #endif
            }

            if bytesRead > 0 {
                data.removeSubrange(bytesRead ..< data.count)
                return data
            }
            if bytesRead == 0 {
                return nil
            }
            if errno == EINTR {
                continue
            }

            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

struct InputScan {
    let containsNonWhitespace: Bool
    let maximumBufferedBytes: Int
    let oversizedLinesTruncated: Int
}

struct StreamingLineReader {
    private let chunkSize: Int
    private let maximumLineBytes: Int
    private var pendingBytes = Data()
    private var receivedBytes = false
    private var endedWithNewline = false
    private var containsNonWhitespace = false
    private var isDiscardingOversizedLine = false
    private var maximumBufferedBytes = 0
    private var oversizedLinesTruncated = 0

    init(chunkSize: Int = 64 * 1024, maximumLineBytes: Int = LineParser.maximumLineBytes) {
        precondition(chunkSize > 0, "chunkSize must be greater than zero")
        precondition(maximumLineBytes > 0, "maximumLineBytes must be greater than zero")
        self.chunkSize = chunkSize
        self.maximumLineBytes = maximumLineBytes
    }

    mutating func consume<Source: InputChunkSource>(
        from source: inout Source,
        onLine: (String) throws -> Void
    ) throws -> InputScan {
        try consumeFramed(from: &source) { framedLine in
            try onLine(framedLine.text)
        }
    }

    mutating func consumeFramed<Source: InputChunkSource>(
        from source: inout Source,
        onLine: (FramedInputLine) throws -> Void
    ) throws -> InputScan {
        while let chunk = try source.read(upToCount: chunkSize) {
            guard !chunk.isEmpty else { continue }
            receivedBytes = true
            endedWithNewline = chunk.last == 0x0A

            try chunk.withUnsafeBytes { buffer in
                var segmentStart = 0
                while let newline = Self.firstNewline(in: buffer, startingAt: segmentStart) {
                    try emitCompleteSegment(buffer[segmentStart ..< newline], to: onLine)
                    segmentStart = newline + 1
                }
                append(buffer[segmentStart...])
            }
        }

        if isDiscardingOversizedLine || !pendingBytes.isEmpty {
            try emitPendingLine(to: onLine)
        } else if receivedBytes && endedWithNewline {
            try onLine(FramedInputLine("", maximumBytes: maximumLineBytes))
        }

        return InputScan(
            containsNonWhitespace: containsNonWhitespace,
            maximumBufferedBytes: maximumBufferedBytes,
            oversizedLinesTruncated: oversizedLinesTruncated
        )
    }

    private static func firstNewline(
        in buffer: UnsafeRawBufferPointer,
        startingAt start: Int
    ) -> Int? {
        guard start < buffer.count, let baseAddress = buffer.baseAddress else { return nil }

        #if canImport(Darwin)
            let match = Darwin.memchr(baseAddress.advanced(by: start), 0x0A, buffer.count - start)
        #elseif canImport(Glibc)
            let match = Glibc.memchr(baseAddress.advanced(by: start), 0x0A, buffer.count - start)
        #elseif canImport(Musl)
            let match = Musl.memchr(baseAddress.advanced(by: start), 0x0A, buffer.count - start)
        #endif

        guard let match else { return nil }
        return baseAddress.distance(to: UnsafeRawPointer(match))
    }

    private mutating func emitCompleteSegment<Bytes: Collection>(
        _ bytes: Bytes,
        to onLine: (FramedInputLine) throws -> Void
    ) throws where Bytes.Element == UInt8 {
        if isDiscardingOversizedLine || !pendingBytes.isEmpty {
            append(bytes)
            try emitPendingLine(to: onLine)
            return
        }

        guard bytes.count <= maximumLineBytes else {
            oversizedLinesTruncated += 1
            containsNonWhitespace = true
            maximumBufferedBytes = max(maximumBufferedBytes, maximumLineBytes)
            let prefix = Data(bytes.prefix(maximumLineBytes))
            try onLine(
                FramedInputLine(
                    Self.decodeUTF8Prefix(prefix),
                    maximumBytes: maximumLineBytes,
                    isTruncated: true
                )
            )
            return
        }

        maximumBufferedBytes = max(maximumBufferedBytes, bytes.count)
        try emitDecodedLine(
            FramedInputLine(
                String(decoding: bytes, as: UTF8.self),
                maximumBytes: maximumLineBytes
            ),
            to: onLine
        )
    }

    private mutating func append<Bytes: Collection>(_ bytes: Bytes) where Bytes.Element == UInt8 {
        guard !bytes.isEmpty, !isDiscardingOversizedLine else { return }
        let remainingCapacity = maximumLineBytes - pendingBytes.count
        guard bytes.count <= remainingCapacity else {
            if remainingCapacity > 0 {
                pendingBytes.append(contentsOf: bytes.prefix(remainingCapacity))
                maximumBufferedBytes = max(maximumBufferedBytes, pendingBytes.count)
            }
            isDiscardingOversizedLine = true
            return
        }
        pendingBytes.append(contentsOf: bytes)
        maximumBufferedBytes = max(maximumBufferedBytes, pendingBytes.count)
    }

    private mutating func emitPendingLine(
        to onLine: (FramedInputLine) throws -> Void
    ) throws {
        if isDiscardingOversizedLine {
            oversizedLinesTruncated += 1
            isDiscardingOversizedLine = false
            let line = FramedInputLine(
                Self.decodeUTF8Prefix(pendingBytes),
                maximumBytes: maximumLineBytes,
                isTruncated: true
            )
            pendingBytes.removeAll(keepingCapacity: true)
            // The bytes are intentionally unavailable for a full Unicode whitespace scan. Treat
            // any oversized line as content so a real build invocation is never rejected as empty.
            containsNonWhitespace = true
            try onLine(line)
            return
        }

        let line = FramedInputLine(
            String(decoding: pendingBytes, as: UTF8.self),
            maximumBytes: maximumLineBytes
        )
        pendingBytes.removeAll(keepingCapacity: true)
        try emitDecodedLine(line, to: onLine)
    }

    private mutating func emitDecodedLine(
        _ line: FramedInputLine,
        to onLine: (FramedInputLine) throws -> Void
    ) throws {
        if !containsNonWhitespace {
            let whitespace = CharacterSet.whitespacesAndNewlines
            containsNonWhitespace = line.text.unicodeScalars.contains {
                !whitespace.contains($0)
            }
        }
        try onLine(line)
    }

    private static func decodeUTF8Prefix(_ bytes: Data) -> String {
        if let decoded = String(data: bytes, encoding: .utf8) { return decoded }

        var prefix = bytes
        for _ in 0 ..< 3 where !prefix.isEmpty {
            prefix.removeLast()
            if let decoded = String(data: prefix, encoding: .utf8) { return decoded }
        }

        // Preserve the existing replacement-character behavior for genuinely invalid input;
        // valid UTF-8 split at the framing boundary always succeeds in the loop above.
        return String(decoding: bytes, as: UTF8.self)
    }
}
