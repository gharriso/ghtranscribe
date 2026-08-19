import AVFoundation
import Foundation

enum TitleResolver {
    /// Determines a title for a recording: a matching calendar event if one
    /// overlaps the recording's actual date/time, otherwise an LLM-generated
    /// one-line summary that includes the date.
    static func resolveTitle(fileURL: URL, transcript: String) async -> String {
        let (recordingDate, duration) = await fileMetadata(fileURL)

        if let eventTitle = await CalendarLookup.matchingEventTitle(around: recordingDate, duration: duration) {
            return eventTitle
        }

        if let llmTitle = try? await OpenAIClient.shared.generateTitle(transcript: transcript, date: recordingDate) {
            return llmTitle
        }

        return dateFormatter.string(from: recordingDate)
    }

    private static func fileMetadata(_ url: URL) async -> (date: Date, duration: TimeInterval) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()

        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let date = values?.creationDate ?? values?.contentModificationDate ?? Date()
        let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 1800

        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
        return (date, duration)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
