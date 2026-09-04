import Foundation
import Testing
@testable import GlazeCore

/// ffmpeg carries ASS styling across as `<font>` markup when it converts a sidecar to
/// SRT. Nothing downstream strips tags, so the parser is the only thing standing
/// between that markup and the viewer's screen.
@Suite struct SubtitleParserMarkupTests {
    private func write(_ contents: String, extension pathExtension: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glaze-markup-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func stripsTheFontMarkupFFmpegEmitsWhenConvertingASS() throws {
        let url = try write(
            """
            1
            00:00:01,000 --> 00:00:03,000
            <font size="20">こんにちは世界</font>

            2
            00:00:04,500 --> 00:00:07,250
            <font size="20"><i>ネットワーク字幕のテスト</i></font>

            """,
            extension: "srt"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let cues = try SubtitleParser.parse(url: url)
        #expect(cues.count == 2)
        #expect(cues[0].text == "こんにちは世界")
        #expect(cues[1].text == "ネットワーク字幕のテスト")
        #expect(cues[1].startTime == 4.5)
        #expect(cues[1].endTime == 7.25)
    }
}
