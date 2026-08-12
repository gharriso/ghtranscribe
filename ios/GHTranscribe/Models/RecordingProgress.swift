import Foundation

struct RecordingProgress: Equatable {
    enum Stage: Equatable {
        case downloading
        case uploading(fraction: Double)
        case waitingForTranscription
        case summarizing
    }

    var stage: Stage
    var startedAt: Date
}
