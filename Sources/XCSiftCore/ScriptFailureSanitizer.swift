import Foundation

enum ScriptFailureSanitizer {
    static let redaction = "<redacted>"
    static let truncationSuffix = "… [truncated]"

    static func sanitize(_ value: String) -> String {
        let tokens = shellTokens(value)
        guard !tokens.isEmpty else { return value }

        var sanitized: [String] = []
        sanitized.reserveCapacity(tokens.count)
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            let matchingToken = canonicalToken(token)

            if matchingToken.hasPrefix("-H"), !matchingToken.hasPrefix("--"),
                matchingToken.count > 2
            {
                sanitized.append("-H" + redaction)
                index += 1
                continue
            }

            if let header = sensitiveHeader(in: matchingToken) {
                sanitized.append(header.name + ":")
                sanitized.append(redaction)
                index +=
                    header.hasValue
                    ? 1
                    : 1 + authorizationValueTokenCount(tokens, startingAt: index + 1)
                continue
            }

            let delimiter = attachedValueDelimiter(in: matchingToken)
            let key = delimiter.map { String(matchingToken[..<$0]) } ?? matchingToken
            let normalizedKey = normalize(key.trimmingCharacters(in: CharacterSet(charactersIn: ":")))

            if isHeaderOption(matchingToken, normalizedKey: normalizedKey) {
                if let delimiter {
                    sanitized.append(String(matchingToken[...delimiter]) + redaction)
                    index += 1
                } else {
                    sanitized.append(token)
                    sanitized.append(redaction)
                    index += 1 + headerValueTokenCount(tokens, startingAt: index + 1)
                }
                continue
            }

            if let delimiter,
                isSensitiveKey(normalizedKey) || isDartDefinesKey(normalizedKey)
            {
                sanitized.append(String(matchingToken[...delimiter]) + redaction)
                index += 1
                continue
            }

            if isStandaloneURLToken(matchingToken) {
                sanitized.append(sanitizeURLToken(token, canonical: matchingToken))
                index += 1
                continue
            }

            let isSensitiveOption =
                matchingToken.hasPrefix("-")
                && (isSensitiveKey(normalizedKey) || isDartDefinesKey(normalizedKey))
            let isSensitiveEnvironmentKey =
                matchingToken == matchingToken.uppercased()
                && isSensitiveKey(normalizedKey)
            if isSensitiveOption || isSensitiveEnvironmentKey {
                sanitized.append(token)
                if index + 1 < tokens.count {
                    sanitized.append(redaction)
                    index += 2
                } else {
                    sanitized.append(redaction)
                    index += 1
                }
                continue
            }

            sanitized.append(sanitizeURLToken(token, canonical: matchingToken))
            index += 1
        }

        return sanitized.joined(separator: " ")
    }

    private static func shellTokens(_ value: String) -> [String] {
        var tokens: [String] = []
        var token = String()
        var activeQuote: Character?
        var isEscaping = false

        func appendToken() {
            guard !token.isEmpty else { return }
            tokens.append(token)
            token.removeAll(keepingCapacity: true)
        }

        for character in value {
            if isEscaping {
                token.append(character)
                isEscaping = false
                continue
            }

            if character == "\\", activeQuote != "'" {
                token.append(character)
                isEscaping = true
                continue
            }

            if let quote = activeQuote {
                token.append(character)
                if character == quote { activeQuote = nil }
                continue
            }

            if character == "'" || character == "\"" {
                activeQuote = character
                token.append(character)
            } else if character.isWhitespace {
                appendToken()
            } else {
                token.append(character)
            }
        }

        appendToken()
        return tokens
    }

    static func sanitizeAndBound(
        _ value: String,
        maximumBytes: Int,
        wasTruncated: Bool = false
    ) -> String {
        bounded(sanitize(value), maximumBytes: maximumBytes, forceSuffix: wasTruncated)
    }

    static func bounded(
        _ value: String,
        maximumBytes: Int,
        forceSuffix: Bool = false
    ) -> String {
        precondition(maximumBytes >= truncationSuffix.utf8.count)
        guard forceSuffix || value.utf8.count > maximumBytes else { return value }

        let prefixBudget = maximumBytes - truncationSuffix.utf8.count
        var prefix = String()
        prefix.reserveCapacity(prefixBudget)
        var usedBytes = 0
        for scalar in value.unicodeScalars {
            let scalarBytes = scalar.utf8.count
            guard usedBytes + scalarBytes <= prefixBudget else { break }
            prefix.unicodeScalars.append(scalar)
            usedBytes += scalarBytes
        }
        return prefix + truncationSuffix
    }

    private static func normalize(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func isAuthorizationHeader(_ key: String) -> Bool {
        key == "authorization" || key == "proxyauthorization" || key == "cookie"
    }

    private static func isStandaloneURLToken(_ token: String) -> Bool {
        guard let scheme = token.range(of: "://") else { return false }
        guard let equals = token.firstIndex(of: "=") else { return true }
        return scheme.lowerBound < equals
    }

    private static func isHeaderOption(_ token: String, normalizedKey: String) -> Bool {
        token == "-H"
            || (token.hasPrefix("--")
                && (normalizedKey == "header" || normalizedKey == "proxyheader"))
    }

    private static func attachedValueDelimiter(in token: String) -> String.Index? {
        switch (token.firstIndex(of: "="), token.firstIndex(of: ":")) {
        case (let equals?, let colon?):
            return min(equals, colon)
        case (let equals?, nil):
            return equals
        case (nil, let colon?):
            return colon
        case (nil, nil):
            return nil
        }
    }

    private static func sensitiveHeader(in token: String) -> (name: String, hasValue: Bool)? {
        let unquoted = strippingMatchingQuotes(from: token)
        guard let colon = unquoted.firstIndex(of: ":") else { return nil }

        let name = String(unquoted[..<colon])
        guard isAuthorizationHeader(normalize(name)) else { return nil }

        let value = unquoted[unquoted.index(after: colon)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, !value.isEmpty)
    }

    private static func strippingMatchingQuotes(from token: String) -> String {
        guard token.count >= 2, let first = token.first, let last = token.last,
            first == last, first == "'" || first == "\""
        else {
            return token
        }
        return String(token.dropFirst().dropLast())
    }

    private static func canonicalToken(_ token: String) -> String {
        var canonical = String()
        canonical.reserveCapacity(token.count)
        var activeQuote: Character?
        var isEscaping = false

        for character in token {
            if isEscaping {
                canonical.append(character)
                isEscaping = false
                continue
            }

            if character == "\\", activeQuote != "'" {
                isEscaping = true
                continue
            }

            if let quote = activeQuote {
                if character == quote {
                    activeQuote = nil
                } else {
                    canonical.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                activeQuote = character
            } else {
                canonical.append(character)
            }
        }

        if isEscaping { canonical.append("\\") }
        return canonical
    }

    private static func authorizationValueTokenCount(
        _ tokens: [String],
        startingAt index: Int
    ) -> Int {
        guard index < tokens.count else { return 0 }
        let firstValue = canonicalToken(tokens[index]).lowercased()
        if ["bearer", "basic"].contains(firstValue) {
            return min(2, tokens.count - index)
        }
        return 1
    }

    private static func headerValueTokenCount(_ tokens: [String], startingAt index: Int) -> Int {
        guard index < tokens.count else { return 0 }
        guard let header = sensitiveHeader(in: tokens[index]), !header.hasValue else { return 1 }
        return 1 + authorizationValueTokenCount(tokens, startingAt: index + 1)
    }

    private static func isDartDefinesKey(_ key: String) -> Bool {
        key == "dartdefine" || key == "dartdefines" || key == "dartdefinefromfile"
            || key == "ddartdefines"
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let fragments = [
            "token", "secret", "password", "passwd", "apikey", "accesskey",
            "authorization", "cookie", "credential", "privatekey", "signature",
        ]
        return fragments.contains { key.contains($0) }
    }

    private static func sanitizeURL(_ token: String) -> String {
        var result = token

        if let schemeRange = result.range(of: "://") {
            let authorityStart = schemeRange.upperBound
            let authorityEnd =
                result[authorityStart...].firstIndex(where: { "/?#".contains($0) })
                ?? result.endIndex
            let authority = result[authorityStart ..< authorityEnd]
            if let atSign = authority.lastIndex(of: "@"), atSign > authority.startIndex {
                result.replaceSubrange(authority.startIndex ..< atSign, with: redaction)
            }
        }

        if let fragmentStart = result.firstIndex(of: "#") {
            let valueStart = result.index(after: fragmentStart)
            let sanitizedFragment = sanitizeKeyValueComponent(result[valueStart...])
            result.replaceSubrange(valueStart..., with: sanitizedFragment)
        }

        if let queryStart = result.firstIndex(of: "?") {
            let valueStart = result.index(after: queryStart)
            let fragmentStart = result[valueStart...].firstIndex(of: "#") ?? result.endIndex
            let sanitizedQuery = sanitizeKeyValueComponent(result[valueStart ..< fragmentStart])
            result.replaceSubrange(valueStart ..< fragmentStart, with: sanitizedQuery)
        }
        return result
    }

    private static func sanitizeKeyValueComponent(_ component: Substring) -> String {
        component.split(separator: "&", omittingEmptySubsequences: false).map { item in
            let parts = item.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard let rawKey = parts.first else { return String(item) }
            let key = String(rawKey)
            guard parts.count == 2, isSensitiveKey(normalize(key)) else {
                return String(item)
            }
            return key + "=" + redaction
        }.joined(separator: "&")
    }

    private static func sanitizeURLToken(_ token: String, canonical: String) -> String {
        let sanitized = sanitizeURL(canonical)
        return sanitized == canonical ? token : sanitized
    }
}
