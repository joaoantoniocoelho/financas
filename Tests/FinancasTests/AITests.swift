import XCTest
@testable import Financas

final class AITests: XCTestCase {
    private let configuration = AIConfiguration(baseURL: "http://localhost:11434", model: "test")

    func testDefaultTransportUsesTheLocalNetworkSession() {
        XCTAssertTrue(OllamaTransport().session === OllamaNetworking.session)
        XCTAssertTrue(OllamaNetworking.session.configuration.waitsForConnectivity)
        XCTAssertEqual(OllamaNetworking.session.configuration.urlCache?.diskCapacity ?? 0, 0)
    }

    func testOfflineErrorIdentifiesOllamaInsteadOfClaimingInternetIsRequired() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineAIURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await AIService(transport: OllamaTransport(session: session)).run(AIConnectionCheck(), configuration: self.configuration)
            XCTFail("Expected a connection failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("localhost:11434"))
            XCTAssertTrue(error.localizedDescription.contains("-1009"))
            XCTAssertTrue(error.localizedDescription.contains("Rede Local"))
        }
    }

    func testLocalOllamaExtraction() async throws {
        guard let url = ProcessInfo.processInfo.environment["FINANCAS_AI_SMOKE_URL"] else {
            throw XCTSkip("Set FINANCAS_AI_SMOKE_URL to run against a local Ollama server.")
        }
        let model = ProcessInfo.processInfo.environment["FINANCAS_AI_SMOKE_MODEL"] ?? "qwen3.5:9b"
        let extraction = ExpenseExtraction(text: "Gastei 42,90 no almoço no pix e 89 de Uber no cartão ontem.")
        let output = try await AIService().run(extraction, configuration: AIConfiguration(baseURL: url, model: model))
        XCTAssertEqual(output.expenses.count, 2)
        let lunch = try XCTUnwrap(output.expenses.first { $0.amountID == "a0" })
        let uber = try XCTUnwrap(output.expenses.first { $0.amountID == "a1" })
        XCTAssertEqual(lunch.payment, PaymentMethod.pix.rawValue)
        XCTAssertEqual(uber.payment, PaymentMethod.card.rawValue)
        XCTAssertEqual(lunch.dateID, "d0")
        XCTAssertEqual(uber.dateID, "d0")
        XCTAssertEqual(lunch.category, "Alimentação fora")
        XCTAssertEqual(uber.category, "Transporte/Uber")
    }

    func testPreprocessingResolvesMoneyAndDatesBeforeInference() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let task = ExpenseExtraction(text: "Ontem paguei 1.234,56 no pix; em 30/12/2025 gastei 89 no cartão", now: now, calendar: calendar)
        XCTAssertEqual(task.amounts.map(\.value), ["1234.56", "89"])
        XCTAssertEqual(task.dates.map(\.value), ["2025-12-31", "2025-12-30"])
        XCTAssertTrue(task.input.contains("2025-12-31"))
    }

    func testMissingAndInvalidDatesAreNotInvented() {
        let task = ExpenseExtraction(text: "almoço 42,90 em 31/02/2026")
        XCTAssertTrue(task.dates.isEmpty)
        XCTAssertEqual(task.amounts.map(\.value), ["42.9"])
        XCTAssertTrue(ExpenseExtraction(text: "almoço quarenta reais").amounts.isEmpty)
    }

    func testPunctuationAndISODatesDoNotCorruptMoney() {
        let task = ExpenseExtraction(text: "Em 2026-09-14 paguei 89. Outro: 42,90. Não usar -12 nem 1.23.")
        XCTAssertEqual(task.amounts.map(\.value), ["89", "42.9"])
        XCTAssertEqual(task.dates.map(\.value), ["2026-09-14"])
    }

    func testPaymentAliasesAreResolvedBeforeInference() throws {
        let task = ExpenseExtraction(text: "42 no PIX, 89 no crédito e 20 no débito automático")
        XCTAssertEqual(task.payments.map(\.value), ["Débito/PIX", "Cartão", "Débito automático"])
        let json = #"{"expenses":[{"description":"Almoço","category":"Outros","amountID":"a0","dateID":"","payment":"Dinheiro"}]}"#
        XCTAssertThrowsError(try task.validate(JSONDecoder().decode(ExpenseExtraction.Output.self, from: Data(json.utf8))))
    }

    func testServiceRejectsUnknownKeysAndInventedCandidateIDs() async throws {
        let task = ExpenseExtraction(text: "almoço 42,90 ontem no pix")
        for json in [
            #"{"expenses":[],"extra":"ignored?"}"#,
            #"{"expenses":[{"description":"Almoço","category":"Alimentação fora","amountID":"inventado","dateID":"d0","payment":"Débito/PIX"}]}"#,
            #"{"expenses":[{"description":"Almoço","category":"Alimentação fora","amountID":"a0","dateID":"d0","payment":"Débito/PIX","amount":100}]}"#,
            #"{"expenses":null}"#,
            "Aqui está: {}"
        ] {
            do {
                _ = try await AIService(transport: StubTransport(json: json)).run(task, configuration: configuration)
                XCTFail("Accepted invalid response: \(json)")
            } catch {}
        }
    }

    func testServiceAcceptsExplicitMissingInformation() async throws {
        let task = ExpenseExtraction(text: "comprei almoço")
        let json = #"{"expenses":[{"description":"Almoço","category":"Alimentação fora","amountID":"","dateID":"","payment":""}]}"#
        let output = try await AIService(transport: StubTransport(json: json)).run(task, configuration: configuration)
        XCTAssertEqual(output.expenses.count, 1)
        XCTAssertEqual(output.expenses[0].amountID, "")
    }

    func testTransportRequiresSchemaAndDisablesThinking() async throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [AIURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let output = try await AIService(transport: OllamaTransport(session: session)).run(AIConnectionCheck(), configuration: configuration)
        XCTAssertEqual(output.status, "conexao ativa")
    }

    func testBatchUsesExistingBalanceRulesAndRollsBackOnFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try Database(url: directory.appendingPathComponent("test.sqlite"))
        let id = try database.createMonth(year: 2026, month: 9, initialBalance: 1000)
        func expense(_ method: PaymentMethod, amount: Double, monthID: Int64, included: Bool = false) -> Expense {
            Expense(id: 0, monthID: monthID, recurringID: nil, date: .now, description: "Teste", category: "Outros", amount: amount, paymentMethod: method, status: .pending, competenceYear: nil, competenceMonth: nil, notes: "", isRecurring: false, includedInInitialBalance: included)
        }
        try database.saveExpenseBatch([expense(.pix, amount: 42.90, monthID: id), expense(.card, amount: 89, monthID: id), expense(.cash, amount: 10, monthID: id, included: true)])
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 957.10, accuracy: 0.001)
        XCTAssertEqual(try database.expenses(monthID: id).filter { $0.status == .invoice }.count, 1)
        XCTAssertThrowsError(try database.saveExpenseBatch([expense(.pix, amount: 50, monthID: id), expense(.pix, amount: 1, monthID: -999)]))
        XCTAssertEqual(try database.expenses(monthID: id).count, 3)
        XCTAssertEqual(try XCTUnwrap(database.months().first).currentBalance, 957.10, accuracy: 0.001)
    }

    @MainActor
    func testReviewRequiresMissingFieldsAndRejectsInvalidMoney() {
        var draft = AIExpenseView.Draft(description: "Almoço", amount: "42,90", category: "Outros", payment: "", date: nil)
        XCTAssertFalse(draft.valid)
        draft.payment = PaymentMethod.pix.rawValue
        draft.date = .now
        XCTAssertTrue(draft.valid)
        for amount in ["NaN", "-1", "0", "1,234", "1e9", "9999999999"] {
            draft.amount = amount
            XCTAssertFalse(draft.valid)
        }
    }
}

private struct StubTransport: AITransport {
    let json: String
    func response(configuration: AIConfiguration, instructions: String, input: String, schema: [String: Any]) async throws -> Data { Data(json.utf8) }
}

private final class OfflineAIURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

private final class AIURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["think"] as? Bool, false)
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual((body["format"] as? [String: Any])?["type"] as? String, "object")
            XCTAssertEqual((body["options"] as? [String: Any])?["temperature"] as? Int, 0)
            XCTAssertEqual(request.url?.path, "/api/chat")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"message":{"content":"{\"status\":\"conexao ativa\"}"}}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
