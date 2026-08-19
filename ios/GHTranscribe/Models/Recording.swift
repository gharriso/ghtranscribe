import Foundation

struct Recording: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case pending
        case transcribing
        case summarizing
        case done
        case failed
    }

    let id: UUID
    var sourceFilename: String
    var sourceBookmark: Data?
    var createdAt: Date
    var status: Status
    var transcript: String?
    var summaryHTML: String?
    var errorMessage: String?
    var transcriptFileNote: String?
    var title: String?
}
