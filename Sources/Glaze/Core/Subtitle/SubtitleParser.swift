import Foundation

enum SubtitleParser {
    enum ParseError: Error {
        case unsupportedFormat
        case unreadableFile
    }

    static func parse(url: URL) throws -> [SubtitleCue] {
        let fileExtension = url.pathExtension.lowercased()
        let content = try readTextFile(url: url)

        switch fileExtension {
        case "srt", "vtt":
            return parseTimedText(content)
        case "smi":
            return parseSMI(content)
        default:
            throw ParseError.unsupportedFormat
        }
    }

    private static func readTextFile(url: URL) throws -> String {
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1] {
            if let content = try? String(contentsOf: url, encoding: encoding) {
                return content
            }
        }

        throw ParseError.unreadableFile
    }

    private static func parseTimedText(_ content: String) -> [SubtitleCue] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        return normalized
            .components(separatedBy: "\n\n")
            .compactMap(parseTimedTextBlock)
            .filter { !$0.text.isEmpty }
            .sorted { $0.startTime < $1.startTime }
    }

    private static func parseTimedTextBlock(_ block: String) -> SubtitleCue? {
        let lines = block
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.uppercased() != "WEBVTT" }

        guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
            return nil
        }

        let timingParts = lines[timingIndex].components(separatedBy: "-->")
        guard timingParts.count == 2,
              let start = parseTimestamp(timingParts[0]),
              let end = parseTimestamp(timingParts[1])
        else {
            return nil
        }

        let text = lines
            .dropFirst(timingIndex + 1)
            .joined(separator: "\n")
            .cleanedSubtitleText()

        return SubtitleCue(startTime: start, endTime: end, text: text)
    }

    private static func parseTimestamp(_ rawValue: String) -> TimeInterval? {
        let cleaned = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first?
            .replacingOccurrences(of: ",", with: ".")

        guard let cleaned else {
            return nil
        }

        let parts = cleaned.components(separatedBy: ":")
        guard parts.count >= 2 else {
            return nil
        }

        let secondsPart = parts.last ?? "0"
        let minutesPart = parts.dropLast().last ?? "0"
        let hoursPart = parts.count == 3 ? parts.first ?? "0" : "0"

        guard let seconds = Double(secondsPart),
              let minutes = Double(minutesPart),
              let hours = Double(hoursPart)
        else {
            return nil
        }

        return hours * 3600 + minutes * 60 + seconds
    }

    private static func parseSMI(_ content: String) -> [SubtitleCue] {
        let pattern = #"(?is)<sync\s+start\s*=\s*"?(\d+)"?[^>]*>(.*?)(?=<sync\s+start\s*=|</body>|</sami>|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, range: range)

        var entries: [(start: TimeInterval, text: String)] = []

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let startRange = Range(match.range(at: 1), in: content),
                  let bodyRange = Range(match.range(at: 2), in: content),
                  let startMilliseconds = Double(content[startRange])
            else {
                continue
            }

            let text = String(content[bodyRange]).cleanedSubtitleText()
            guard !text.isEmpty else {
                continue
            }

            entries.append((start: startMilliseconds / 1000, text: text))
        }

        return entries.enumerated().map { index, entry in
            let nextStart = entries.dropFirst(index + 1).first?.start
            let end = nextStart ?? entry.start + 4
            return SubtitleCue(startTime: entry.start, endTime: end, text: entry.text)
        }
    }
}

private extension String {
    func cleanedSubtitleText() -> String {
        replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
