import Foundation

struct AIConfiguration {
    var baseURL: String
    var model: String
}

/// Each use case owns its schema, context preparation and semantic validation.
protocol StructuredAITask {
    associatedtype Output: Decodable
    var instructions: String { get }
    var input: String { get }
    var schema: [String: Any] { get }
    func validate(_ output: Output) throws
}

protocol AITransport {
    func response(configuration: AIConfiguration, instructions: String, input: String, schema: [String: Any])
        async throws -> Data
}

struct AIService {
    var transport: any AITransport = OllamaTransport()

    func run<UseCase: StructuredAITask>(_ task: UseCase, configuration: AIConfiguration) async throws -> UseCase.Output
    {
        let data = try await transport.response(
            configuration: configuration, instructions: task.instructions, input: task.input, schema: task.schema)
        try Task.checkCancellation()
        try AISchemaValidator.validate(JSONSerialization.jsonObject(with: data), schema: task.schema)
        let output = try JSONDecoder().decode(UseCase.Output.self, from: data)
        try task.validate(output)
        return output
    }
}

/// Supported schema vocabulary is intentionally small; unknown types fail closed.
enum AISchemaValidator {
    static func validate(_ value: Any, schema: [String: Any]) throws {
        func invalid() -> OllamaClientError { .server("A resposta da IA não corresponde ao formato obrigatório.") }
        switch schema["type"] as? String {
        case "object":
            guard let object = value as? [String: Any],
                let properties = schema["properties"] as? [String: [String: Any]],
                let required = schema["required"] as? [String], Set(required).isSubset(of: Set(object.keys)),
                schema["additionalProperties"] as? Bool == false, Set(object.keys).isSubset(of: Set(properties.keys))
            else { throw invalid() }
            for (key, child) in object { try validate(child, schema: properties[key]!) }
        case "array":
            guard let array = value as? [Any], let items = schema["items"] as? [String: Any],
                array.count <= (schema["maxItems"] as? Int ?? Int.max)
            else { throw invalid() }
            for child in array { try validate(child, schema: items) }
        case "string":
            guard let string = value as? String else { throw invalid() }
            if let allowed = schema["enum"] as? [String], !allowed.contains(string) { throw invalid() }
        default: throw invalid()
        }
    }
}

struct AIConnectionCheck: StructuredAITask {
    struct Output: Decodable { let status: String }
    let instructions = "Responda com o objeto JSON solicitado, status conexao ativa."
    let input = "Teste de conexão."
    var schema: [String: Any] {
        [
            "type": "object", "additionalProperties": false, "required": ["status"],
            "properties": ["status": ["type": "string", "enum": ["conexao ativa"]]],
        ]
    }
    func validate(_ output: Output) throws {}
}

/// Connection checks and inference must use the same network configuration and session.
enum OllamaNetworking {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    static func connectionError(_ error: URLError, url: URL) -> OllamaClientError {
        let destination = url.host.map { host in url.port.map { "\(host):\($0)" } ?? host } ?? "servidor configurado"
        switch error.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
            return .server(
                "Não foi possível acessar o Ollama em \(destination). Verifique o servidor, a rede local e a permissão de Rede Local do Finanças nos Ajustes do Sistema. Código: \(error.errorCode)."
            )
        case .timedOut:
            return .server(
                "O Ollama em \(destination) não respondeu em até 120 segundos. Tente novamente. Código: \(error.errorCode)."
            )
        default:
            return .server(
                "Falha ao acessar o Ollama em \(destination): \(error.localizedDescription) Código: \(error.errorCode)."
            )
        }
    }
}

struct OllamaTransport: AITransport {
    var session: URLSession = OllamaNetworking.session

    func response(configuration: AIConfiguration, instructions: String, input: String, schema: [String: Any])
        async throws -> Data
    {
        guard let url = URL(string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["http", "https"].contains(url.scheme), url.host != nil,
            !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw OllamaClientError.invalidURL
        }
        var request = URLRequest(url: url.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model, "stream": false, "think": false,
            "format": schema, "options": ["temperature": 0],
            "messages": [["role": "system", "content": instructions], ["role": "user", "content": input]],
        ])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw OllamaNetworking.connectionError(error, url: url)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OllamaClientError.server(
                "O servidor recusou a solicitação estruturada (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))."
            )
        }
        struct Envelope: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let result = envelope.message.content.data(using: .utf8), !result.isEmpty else {
            throw OllamaClientError.emptyResponse
        }
        return result
    }
}
