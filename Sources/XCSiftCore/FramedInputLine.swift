/// A single physical input line after applying xcsift's bounded UTF-8 framing policy.
///
/// Package visibility keeps the CLI reader and core parser on the same contract without
/// expanding the public library API. Truncated lines retain only a valid UTF-8 prefix.
package struct FramedInputLine: Sendable {
    package let text: String
    package let isTruncated: Bool

    package init(
        _ text: String,
        maximumBytes: Int = LineParser.maximumLineBytes,
        isTruncated: Bool = false
    ) {
        precondition(maximumBytes > 0)
        let exceedsLimit = text.utf8.count > maximumBytes
        self.text = exceedsLimit ? Self.prefix(text, maximumBytes: maximumBytes) : text
        self.isTruncated = isTruncated || exceedsLimit
    }

    private static func prefix(_ text: String, maximumBytes: Int) -> String {
        var result = String()
        result.reserveCapacity(maximumBytes)
        var usedBytes = 0

        for scalar in text.unicodeScalars {
            let scalarBytes = scalar.utf8.count
            guard usedBytes + scalarBytes <= maximumBytes else { break }
            result.unicodeScalars.append(scalar)
            usedBytes += scalarBytes
        }
        return result
    }
}
