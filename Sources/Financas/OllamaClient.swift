import Foundation

struct OllamaConnectionResult {
    let model: String
    let availableModels: [String]
    let response: String
    let latency: TimeInterval
}

enum OllamaClientError: LocalizedError {
    case invalidURL
    case server(String)
    case modelUnavailable(String, available: [String])
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "A URL do Ollama é inválida. Use, por exemplo, http://192.168.0.250:11434."
        case .server(let message):
            return message
        case .modelUnavailable(let model, let available):
            if available.isEmpty {
                return "O modelo \"\(model)\" não está disponível no servidor. Nenhum modelo foi encontrado."
            }
            return
                "O modelo \"\(model)\" não está disponível. Modelos encontrados: \(available.joined(separator: ", "))."
        case .emptyResponse:
            return "O Ollama respondeu, mas não retornou texto."
        }
    }
}

struct OllamaClient {
    private let session: URLSession

    init(session: URLSession = OllamaNetworking.session) {
        self.session = session
    }

    func test(baseURL: String, model: String) async throws -> OllamaConnectionResult {
        guard let rootURL = normalizedURL(baseURL) else { throw OllamaClientError.invalidURL }

        let tagsURL = rootURL.appendingPathComponent("api/tags")
        let startedAt = Date()
        let tags: TagsResponse
        do {
            tags = try await get(tagsURL, as: TagsResponse.self)
        } catch {
            throw map(error, baseURL: baseURL)
        }

        let availableModels = tags.models.map(\.name)
        guard availableModels.contains(model) else {
            throw OllamaClientError.modelUnavailable(model, available: availableModels)
        }

        do {
            let result = try await AIService(transport: OllamaTransport(session: session)).run(
                AIConnectionCheck(), configuration: AIConfiguration(baseURL: baseURL, model: model))
            return OllamaConnectionResult(
                model: model, availableModels: availableModels, response: result.status,
                latency: Date().timeIntervalSince(startedAt))
        } catch {
            throw map(error, baseURL: baseURL)
        }
    }

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(type, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let serverMessage =
                (try? JSONDecoder().decode(ErrorResponse.self, from: data).error) ?? "respondeu com erro HTTP"
            throw OllamaClientError.server("O Ollama \(serverMessage).")
        }
    }

    private func normalizedURL(_ value: String) -> URL? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.hasSuffix("/") { text.append("/") }
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil
        else { return nil }
        return url
    }

    private func map(_ error: Error, baseURL: String) -> Error {
        if let ollamaError = error as? OllamaClientError { return ollamaError }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return OllamaClientError.server("a conexão com \(baseURL) excedeu o tempo limite")
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return OllamaClientError.server(
                    "não foi possível conectar a \(baseURL) (\(urlError.localizedDescription))")
            default: break
            }
        }
        let nsError = error as NSError
        return OllamaClientError.server(
            "não foi possível testar o Ollama: \(error.localizedDescription) [\(nsError.domain):\(nsError.code)]")
    }

    private struct TagsResponse: Decodable { let models: [Model] }
    private struct Model: Decodable { let name: String }
    private struct ErrorResponse: Decodable { let error: String }
}
