import Darwin
import Foundation
import os

/// Kinds of sensitive information recognized in screenshots.
nonisolated enum SensitiveTextKind: String, CaseIterable, Sendable {
    case email
    case phoneNumber
    case paymentCard
    case ipAddress
    case secretURL
    case accessToken
    case iban

    /// Secrets and financial numbers: blurred or pixelated text can sometimes be recovered,
    /// so these are always hidden with a solid fill.
    var needsSolidFill: Bool {
        switch self {
        case .accessToken, .secretURL, .paymentCard, .iban: true
        case .email, .phoneNumber, .ipAddress: false
        }
    }
}

/// Matches text against patterns for personal data and secrets.
///
/// Pure string logic with no I/O, safe to call from any thread.
nonisolated enum SensitiveTextPatterns {

    /// A sensitive substring.
    struct Match: Equatable, Sendable {
        let kind: SensitiveTextKind
        let range: Range<String.Index>
    }

    /// Returns the sensitive substrings of `text`, sorted, with overlapping matches merged.
    ///
    /// Look-alike characters (Cyrillic “о”, fullwidth “＠”, typographic dashes…) are matched
    /// as their ASCII counterparts; the returned ranges still refer to `text`.
    static func matches(in text: String) -> [Match] {
        guard let folded = foldingConfusables(text) else {
            return rawMatches(in: text)
        }
        // Folding replaces scalars one for one, so offsets carry over to the original text.
        let originalIndices = Array(text.unicodeScalars.indices) + [text.unicodeScalars.endIndex]
        let foldedScalars = folded.unicodeScalars
        return rawMatches(in: folded).map { match in
            let lower = foldedScalars.distance(from: foldedScalars.startIndex, to: match.range.lowerBound)
            let upper = foldedScalars.distance(from: foldedScalars.startIndex, to: match.range.upperBound)
            return Match(kind: match.kind, range: originalIndices[lower]..<originalIndices[upper])
        }
    }

    /// Whether `text` opens a private key block (`-----BEGIN … PRIVATE KEY-----`).
    static func isPrivateKeyHeader(_ text: String) -> Bool {
        privateKeyHeader?.hasMatch(in: text, foldingConfusables: true) ?? false
    }

    /// Whether `text` closes a private key block (`-----END … PRIVATE KEY-----`).
    static func isPrivateKeyFooter(_ text: String) -> Bool {
        privateKeyFooter?.hasMatch(in: text, foldingConfusables: true) ?? false
    }

    /// Whether `text` can be a line inside a private key block: base64 data, or a PEM header
    /// such as `Proc-Type:`.
    static func isPrivateKeyBody(_ text: String) -> Bool {
        let folded = foldingConfusables(text) ?? text
        if privateKeyBody?.hasMatch(in: folded, foldingConfusables: false) ?? false {
            return true
        }
        // Text recognition can misread a few characters of a long base64 line.
        let line = folded.trimmingCharacters(in: .whitespaces)
        let misread = line.unicodeScalars.filter { !base64Line.contains($0) }.count
        return line.count >= 16 && misread <= max(1, line.count / 20)
    }

    // MARK: - Rules

    private struct Rule: Sendable {
        let kind: SensitiveTextKind
        let regex: NSRegularExpression
        /// Capture group holding the sensitive part (0 for the whole match).
        let group: Int
        /// Validates a candidate, optionally narrowing it. Returns nil to reject it.
        let refine: @Sendable (String, Range<String.Index>) -> Range<String.Index>?
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "clicke", category: "Redaction")

    /// Keywords whose value is a secret, as in `password: …` or `DB_PASSWORD=…`.
    private static let secretKeywords = #"password|passwd|passphrase|passcode|pwd|secret|token|credentials?|api[_\-]?key|access[_\-]?key|secret[_\-]?key|auth[_\-]?key|client[_\-]?secret|private[_\-]?key|(?<=_)pass"#

    /// Ordered by priority: when matches overlap, the earlier rule names the result.
    private static let rules: [Rule] = [
        // Private key blocks (the body is found line by line by `SensitiveTextDetector`).
        rule(.accessToken, #"-{2,}\s*BEGIN [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?\s*-{2,}"#),
        // URLs carrying credentials or secrets in their query.
        rule(.secretURL, #"\b(?:https?|ftp|wss?)://[^\s"'<>]+"#, options: .caseInsensitive, refine: secretURL),
        rule(.email, #"[A-Z0-9._%+\-]+@[A-Z0-9\-]+(?:\.[A-Z0-9\-]+)*\.[A-Z]{2,24}\b"#, options: .caseInsensitive),
        // JSON Web Tokens.
        rule(.accessToken, #"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#),
        // Well-known API key formats: OpenAI/Anthropic, GitHub, Slack, AWS, Google, Stripe, GitLab, npm, Hugging Face.
        rule(.accessToken, #"(?<![A-Za-z0-9])(?:sk-[A-Za-z0-9_\-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[abposr]-[A-Za-z0-9\-]{10,}|(?:AKIA|ASIA)[A-Z0-9]{16}|AIza[0-9A-Za-z_\-]{35}|[rsp]k_(?:live|test)_[A-Za-z0-9]{16,}|glpat-[A-Za-z0-9_\-]{20,}|npm_[A-Za-z0-9]{36}|hf_[A-Za-z0-9]{30,})"#),
        // HTTP credentials: only the credential is hidden.
        rule(.accessToken, #"(?<![A-Za-z0-9])(?:proxy-)?authorization["']?\s*[:=]\s*["']?(?:(?:basic|bearer|digest|negotiate|ntlm|token|apikey|aws4-hmac-sha256)\s+)?([^\s"',;]{6,})"#, options: .caseInsensitive, group: 1),
        rule(.accessToken, #"(?<![A-Za-z0-9])bearer\s+([A-Za-z0-9\-._~+/]{16,}=*)"#, options: .caseInsensitive, group: 1),
        rule(.accessToken, #"(?<![A-Za-z0-9])basic\s+([A-Za-z0-9+/]{4,}={0,2})(?![A-Za-z0-9+/=])"#, options: .caseInsensitive, group: 1, refine: basicCredentials),
        // "password: <value>", "DB_PASSWORD=<value>", "GITHUB_TOKEN=<value>": only the value is hidden.
        rule(.accessToken, #"(?<![A-Za-z0-9])[A-Z0-9_]*(?:"# + secretKeywords + #")["']?\s*[:=]+>?\s*["']?([^\s"',;]{4,})"#, options: .caseInsensitive, group: 1),
        rule(.iban, #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]){11,30}\b"#, refine: iban),
        rule(.paymentCard, #"(?<!\d)(?:\d[ \-]?){12,18}\d(?!\d)"#, refine: paymentCard),
        rule(.ipAddress, #"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?:/\d{1,2}|:\d{1,5})?(?!\.?\d)"#),
        rule(.ipAddress, #"(?<![0-9A-Za-z:])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![0-9A-Za-z:])"#, refine: ipv6),
        rule(.phoneNumber, #"(?<![\w+(])(?:\+|\()?\d[\d \-.()]{6,22}\d(?![\w)])"#, refine: phoneNumber),
        // Long random-looking hex and base64 runs (hashes, keys, session IDs).
        rule(.accessToken, #"(?<![0-9A-Za-z])[0-9A-Fa-f]{24,}(?![0-9A-Za-z])"#, refine: hexToken),
        rule(.accessToken, #"(?<![A-Za-z0-9+/_\-])[A-Za-z0-9+/_\-]{24,}={0,2}(?![A-Za-z0-9+/_=\-])"#, refine: base64Token),
    ].compactMap { $0 }

    private static let privateKeyHeader = regex(#"-{2,}\s*BEGIN [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?\s*-{2,}"#)
    private static let privateKeyFooter = regex(#"-{2,}\s*END [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?\s*-{2,}"#)
    /// Base64 lines (text recognition may split them with spaces) and PEM headers.
    private static let base64Line = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/= ")
    private static let privateKeyBody = regex(#"^\s*(?:[A-Za-z0-9+/=][A-Za-z0-9+/= ]{3,}|(?:Proc-Type|DEK-Info|Comment|Version|Hash):.*)\s*$"#)

    private static func rule(
        _ kind: SensitiveTextKind,
        _ pattern: String,
        options: NSRegularExpression.Options = [],
        group: Int = 0,
        refine: @escaping @Sendable (String, Range<String.Index>) -> Range<String.Index>? = { _, range in range }
    ) -> Rule? {
        regex(pattern, options: options).map { Rule(kind: kind, regex: $0, group: group, refine: refine) }
    }

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            logger.fault("Invalid sensitive text pattern: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Matches `text` as is, without folding look-alike characters.
    private static func rawMatches(in text: String) -> [Match] {
        let nsRange = NSRange(text.startIndex..., in: text)
        var found: [(priority: Int, match: Match)] = []

        for (priority, rule) in rules.enumerated() {
            for result in rule.regex.matches(in: text, range: nsRange) {
                let captured = result.range(at: rule.group)
                guard captured.location != NSNotFound,
                      let range = Range(captured, in: text),
                      let refined = rule.refine(text, range),
                      !refined.isEmpty else { continue }
                found.append((priority, Match(kind: rule.kind, range: refined)))
            }
        }
        return merged(found)
    }

    // MARK: - Look-Alike Characters

    /// `text` with look-alike characters replaced by their ASCII counterparts, scalar for scalar,
    /// or nil when there is nothing to replace.
    static func foldingConfusables(_ text: String) -> String? {
        guard !text.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
        var folded = String.UnicodeScalarView()
        var changed = false
        for scalar in text.unicodeScalars {
            let replacement = asciiLookAlike(of: scalar) ?? scalar
            changed = changed || replacement != scalar
            folded.append(replacement)
        }
        return changed ? String(folded) : nil
    }

    /// Characters from other scripts that render like ASCII letters and symbols.
    private static let lookAlikes: [Unicode.Scalar: Unicode.Scalar] = {
        let pairs: [(String, String)] = [
            // Cyrillic
            ("аеорсхуіјѕԁһԛԝӏк", "aeopcxyijsdhqwlk"),
            ("АВЕКМНОРСТХУІЈЅԚԜӀҮЗ", "ABEKMHOPCTXYIJSQWIY3"),
            // Greek
            ("αοριυνκϲϳ", "aopiuvkcj"),
            ("ΑΒΕΖΗΙΚΜΝΟΡΤΥΧϹ", "ABEZHIKMNOPTYXC"),
            // Armenian and Latin variants; “Ø” is how slashed zeros of code fonts are read.
            ("օսոɑɡıȷØø", "ounagij0o"),
            // Punctuation
            ("‐‑‒–—―−﹘﹣", "---------"),
            ("‘’‚‛′", "'''''"),
            ("“”„‟″", "\"\"\"\"\""),
            ("∕⁄", "//"),
            ("∶꞉ː", ":::"),
        ]
        var table: [Unicode.Scalar: Unicode.Scalar] = [:]
        for (sources, targets) in pairs {
            for (source, target) in zip(sources.unicodeScalars, targets.unicodeScalars) {
                table[source] = target
            }
        }
        return table
    }()

    /// The ASCII scalar `scalar` looks like, if any: cross-script look-alikes, then compatibility
    /// forms such as fullwidth or mathematical letters.
    private static func asciiLookAlike(of scalar: Unicode.Scalar) -> Unicode.Scalar? {
        guard !scalar.isASCII else { return nil }
        if let lookAlike = lookAlikes[scalar] {
            return lookAlike
        }
        let compatible = String(Character(scalar)).precomposedStringWithCompatibilityMapping.unicodeScalars
        guard compatible.count == 1, let only = compatible.first, only.isASCII else { return nil }
        return only
    }

    // MARK: - Validators

    private static let secretQueryKeys = try? NSRegularExpression(
        pattern: #"[?&#;](?:access_token|refresh_token|id_token|token|auth|authorization|api[_\-]?key|key|secret|client_secret|password|passwd|pwd|sig|signature|x-amz-signature|x-amz-credential|x-amz-security-token|session|sessionid|sid|code|jwt|ticket)="#,
        options: .caseInsensitive
    )
    private static let urlCredentials = try? NSRegularExpression(pattern: #"^[a-z][a-z0-9+.\-]*://[^/\s:@]+:[^/\s@]+@"#, options: .caseInsensitive)

    /// Keeps URLs with embedded credentials or secret query parameters, minus trailing punctuation.
    private static func secretURL(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        var end = range.upperBound
        while end > range.lowerBound, let last = text[range.lowerBound..<end].last, ".,;:!?)]}'\"".contains(last) {
            end = text.index(before: end)
        }
        let trimmed = range.lowerBound..<end
        let url = String(text[trimmed])
        let isSecret = [urlCredentials, secretQueryKeys].contains { regex in
            regex?.hasMatch(in: url, foldingConfusables: false) ?? false
        }
        return isSecret ? trimmed : nil
    }

    /// HTTP Basic credentials: base64 of `user:password`.
    private static func basicCredentials(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        var encoded = String(text[range])
        // Text recognition sometimes drops the trailing padding.
        if !encoded.count.isMultiple(of: 4) {
            encoded += String(repeating: "=", count: 4 - encoded.count % 4)
        }
        guard let decoded = Data(base64Encoded: encoded), decoded.contains(UInt8(ascii: ":")) else { return nil }
        return range
    }

    /// Valid IBAN (mod 97). Trailing groups are dropped until the checksum matches, since the
    /// pattern can run into the following words.
    private static func iban(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        var candidate = text[range]
        while true {
            let compact = candidate.filter { !$0.isWhitespace }.uppercased()
            if (15...34).contains(compact.count), isValidIBAN(compact) {
                return candidate.startIndex..<candidate.endIndex
            }
            guard let lastSpace = candidate.lastIndex(of: " ") else { return nil }
            candidate = candidate[..<lastSpace]
        }
    }

    private static func isValidIBAN(_ iban: String) -> Bool {
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for character in rearranged {
            guard let ascii = character.asciiValue else { return false }
            switch ascii {
            case 48...57: // 0–9
                remainder = (remainder * 10 + Int(ascii - 48)) % 97
            case 65...90: // A–Z expand to two digits, A = 10 … Z = 35
                remainder = (remainder * 100 + Int(ascii - 55)) % 97
            default:
                return false
            }
        }
        return remainder == 1
    }

    /// 13–19 digit numbers that pass the Luhn check.
    private static func paymentCard(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        let digits = text[range].compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), Set(digits).count > 1 else { return nil }
        // Luhn: double every second digit from the right.
        let sum = digits.reversed().enumerated().reduce(0) { sum, element in
            let (index, digit) = element
            if index.isMultiple(of: 2) { return sum + digit }
            let doubled = digit * 2
            return sum + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10) ? range : nil
    }

    /// Addresses accepted by `inet_pton`, with at least three groups (skips times and short tokens).
    private static func ipv6(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        let candidate = String(text[range])
        let groups = candidate.split(separator: ":", omittingEmptySubsequences: true)
        guard groups.count >= 3 else { return nil }
        var address = in6_addr()
        return inet_pton(AF_INET6, candidate, &address) == 1 ? range : nil
    }

    private static let containsDate = try? NSRegularExpression(
        pattern: #"(?:^|\D)(?:\d{4}[\-./]\d{1,2}[\-./]\d{1,2}|\d{1,2}[\-./]\d{1,2}[\-./]\d{4})(?:\D|$)"#
    )

    /// 9–15 digits with plausible separators; rejects dates and bare long numbers.
    private static func phoneNumber(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        let candidate = String(text[range])
        let digitCount = candidate.filter(\.isWholeNumber).count
        guard (9...15).contains(digitCount) else { return nil }
        guard candidate.filter({ $0 == "(" }).count == candidate.filter({ $0 == ")" }).count else { return nil }
        guard !candidate.contains("  "), !candidate.contains(".."), !candidate.contains("--") else { return nil }
        if containsDate?.hasMatch(in: candidate, foldingConfusables: false) == true {
            return nil
        }
        let hasSeparators = candidate.contains { !$0.isWholeNumber }
        // A bare run of digits is only a phone number at typical lengths (e.g. 0612345678).
        guard hasSeparators || (10...12).contains(digitCount) else { return nil }
        return range
    }

    private static func hexToken(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        let token = text[range]
        guard token.contains(where: \.isNumber), token.contains(where: \.isLetter) else { return nil }
        return classTransitionRatio(token) >= 0.25 ? range : nil
    }

    /// Mixed-case alphanumeric runs that look random rather than like words, paths, or identifiers.
    private static func base64Token(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        let token = text[range]
        guard token.contains(where: \.isUppercase),
              token.contains(where: \.isLowercase),
              token.contains(where: \.isNumber) else { return nil }
        let slashes = token.filter { $0 == "/" }.count
        guard slashes < 3 || Double(slashes) / Double(token.count) < 0.05 else { return nil }
        guard wordLikeRatio(token) < 0.7 else { return nil }
        return classTransitionRatio(token) >= 0.3 ? range : nil
    }

    /// Share of lowercase letters that sit in runs of three or more. Close to 1 for camel-case
    /// words, around 0.4 for random strings.
    private static func wordLikeRatio(_ token: Substring) -> Double {
        var lowercase = 0
        var inLongRuns = 0
        var run = 0
        for character in token {
            if character.isLowercase {
                lowercase += 1
                run += 1
            } else {
                if run >= 3 { inLongRuns += run }
                run = 0
            }
        }
        if run >= 3 { inLongRuns += run }
        return lowercase == 0 ? 0 : Double(inLongRuns) / Double(lowercase)
    }

    /// Share of adjacent characters that switch between uppercase, lowercase, digit and symbol.
    /// Random strings switch often; words and camel-case identifiers rarely do.
    private static func classTransitionRatio(_ token: Substring) -> Double {
        func characterClass(_ character: Character) -> Int {
            if character.isUppercase { return 0 }
            if character.isLowercase { return 1 }
            if character.isNumber { return 2 }
            return 3
        }
        let classes = token.map(characterClass)
        guard classes.count > 1 else { return 0 }
        let transitions = zip(classes, classes.dropFirst()).filter { $0 != $1 }.count
        return Double(transitions) / Double(classes.count - 1)
    }

    // MARK: - Merging

    /// Sorts matches and merges overlapping ones, keeping the highest-priority kind.
    private static func merged(_ found: [(priority: Int, match: Match)]) -> [Match] {
        let sorted = found.sorted { $0.match.range.lowerBound < $1.match.range.lowerBound }
        var result: [(priority: Int, match: Match)] = []
        for item in sorted {
            guard let last = result.last, item.match.range.lowerBound < last.match.range.upperBound else {
                result.append(item)
                continue
            }
            let range = last.match.range.lowerBound..<max(last.match.range.upperBound, item.match.range.upperBound)
            let winner = item.priority < last.priority ? item : last
            result[result.count - 1] = (winner.priority, Match(kind: winner.match.kind, range: range))
        }
        return result.map(\.match)
    }
}

private extension NSRegularExpression {
    /// Whether the expression matches anywhere in `text`, optionally after folding look-alike characters.
    nonisolated func hasMatch(in text: String, foldingConfusables: Bool) -> Bool {
        let subject = foldingConfusables ? SensitiveTextPatterns.foldingConfusables(text) ?? text : text
        return firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)) != nil
    }
}
