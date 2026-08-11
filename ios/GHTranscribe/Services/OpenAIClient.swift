import Foundation

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case requestFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No OpenAI API key set. Add one in Settings."
        case .requestFailed(let message):
            return message
        case .emptyResponse:
            return "Empty response from OpenAI."
        }
    }
}

final class OpenAIClient {
    static let shared = OpenAIClient()

    private let session = URLSession.shared

    private static let summaryPrompt = """
    You are given the transcript of a recorded conversation. Write a clear, well-organized \
    summary covering the main topics discussed and any decisions or action items. Then add a \
    short section titled 'Observations' with any comments you think are worthwhile -- e.g. open \
    questions, risks, inconsistencies, or follow-ups the speakers may have missed.

    Respond with valid HTML only (no markdown, no code fences, no <html>/<body> wrapper), using \
    only these tags: <b>, <h2>, <ul>, <li>, <table>, <tr>, <td>, <th>, <br>, <p>. Use \
    "<h2>Observations</h2>" as that section's heading.
    """

    private func apiKey() throws -> String {
        guard let key = KeychainStore.loadAPIKey(), !key.isEmpty else {
            throw OpenAIError.missingAPIKey
        }
        return key
    }

    func transcribe(audioData: Data, filename: String) async throws -> String {
        let key = try apiKey()

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: ["model": "gpt-4o-transcribe"],
            fileField: "file",
            filename: filename,
            fileData: audioData,
            fileMimeType: "audio/m4a"
        )

        let (data, response) = try await session.data(for: request)
        try Self.checkResponse(response, data: data)

        struct TranscriptionResponse: Decodable { let text: String }
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
    }

    func summarize(transcript: String) async throws -> String {
        let key = try apiKey()

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": Self.summaryPrompt],
                ["role": "user", "content": transcript],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try Self.checkResponse(response, data: data)

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIError.emptyResponse
        }
        return content
    }

    private static func multipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String,
        filename: String,
        fileData: Data,
        fileMimeType: String
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(string.data(using: .utf8)!)
        }

        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(fileMimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        return body
    }

    private static func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.requestFailed("HTTP \(http.statusCode): \(body)")
        }
    }
}
