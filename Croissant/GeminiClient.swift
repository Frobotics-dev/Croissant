import Foundation

// Gemini API response structure based on your prompt's format
struct GeminiResponse: Decodable {
    let response: String
    let Sentiment: String
}

class GeminiClient {
    private let apiKeyProvider: () -> String?
    private let session = URLSession.shared
    
    enum GeminiError: Error, LocalizedError {
        case missingAPIKey
        case invalidURL
        case networkError(Error)
        case httpError(statusCode: Int, message: String?)
        case decodingError(Error)
        case noContent
        
        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "Gemini API key is not set."
            case .invalidURL: return "The API endpoint URL is invalid."
            case .networkError(let error): return "Network request failed: \(error.localizedDescription)"
            case .httpError(let statusCode, let message): return "API request failed with status code \(statusCode). \(message ?? "")"
            case .decodingError(let error): return "Failed to decode the response from the API. \(error.localizedDescription)"
            case .noContent: return "The API returned no content."
            }
        }
    }

    init(apiKeyProvider: @escaping () -> String?) {
        self.apiKeyProvider = apiKeyProvider
    }

    func generateSummary(prompt: String) async throws -> GeminiResponse {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "response_mime_type": "application/json",
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8)
            throw GeminiError.httpError(statusCode: statusCode, message: message)
        }
        
        struct GeminiAPIResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String
                    }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }
        
        do {
            let decodedResponse = try JSONDecoder().decode(GeminiAPIResponse.self, from: data)
            guard let textContent = decodedResponse.candidates.first?.content.parts.first?.text else {
                throw GeminiError.noContent
            }
            
            if let jsonData = textContent.data(using: .utf8) {
                let innerResponse = try JSONDecoder().decode(GeminiResponse.self, from: jsonData)
                return innerResponse
            } else {
                throw GeminiError.decodingError(NSError(domain: "GeminiClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert Gemini text to data."]))
            }

        } catch {
            throw GeminiError.decodingError(error)
        }
    }
}
