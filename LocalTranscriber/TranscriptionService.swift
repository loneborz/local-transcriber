import AVFoundation
import Speech

enum TranscriptionService {
    static func transcribe(
        url: URL,
        locale: Locale = Locale(identifier: "en-US")
    ) async throws -> String {
        let file = try AVAudioFile(forReading: url)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let transcription: String = try transcriber.results.reduce("") {
            partialResult,
            result in

            partialResult + String(result.text.characters) + "\n"
        }

        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        return try await transcription
    }
}
