@testable import EnchiridionKit
import Foundation
import Testing

@Suite struct ErrorTests {
    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: EnchiridionClient.testServer, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    private func mapped(_ status: Int, _ body: String) -> EnchiridionError {
        EnchiridionError.fromResponse(response(status), body: Data(body.utf8))
    }

    // MARK: Transport

    @Test(arguments: [
        (-1003, EnchiridionError.tailscaleOff),   // cannotFindHost
        (-1006, .tailscaleOff),                   // dnsLookupFailed
        (-1001, .unreachable),                    // timedOut
        (-1004, .unreachable),                    // cannotConnectToHost
        (-1005, .unreachable),                    // networkConnectionLost
        (-1009, .offline),                        // notConnectedToInternet
        (-1020, .offline),                        // dataNotAllowed
        (-1018, .offline),                        // internationalRoamingOff
        (-1200, .offline),                        // secureConnectionFailed
        (-1202, .offline),                        // serverCertificateUntrusted
        (-1206, .offline),                        // clientCertificateRequired
        (-1011, .unreachable),                    // badServerResponse: anything else
        (-1022, .unreachable),                    // appTransportSecurityRequiresSecureConnection
    ])
    func urlErrors(code: Int, expected: EnchiridionError) {
        let error = EnchiridionError.fromTransport(URLError(URLError.Code(rawValue: code)))
        #expect(error as? EnchiridionError == expected)
    }

    @Test func cancellationStaysCancellation() {
        #expect(EnchiridionError.fromTransport(URLError(.cancelled)) is CancellationError)
        #expect(EnchiridionError.fromTransport(CancellationError()) is CancellationError)
    }

    @Test func otherErrorsReadAsUnreachable() {
        struct Odd: Error {}
        #expect(EnchiridionError.fromTransport(Odd()) as? EnchiridionError == .unreachable)
        #expect(EnchiridionError.fromTransport(EnchiridionError.restarting) as? EnchiridionError == .restarting)
    }

    // MARK: Responses

    @Test func unauthorizedWithDevice() {
        #expect(mapped(401, Fixture.unauthorizedKnown) == .unauthorized(device: Device(id: "nXYZ123CNTRL", name: "vern")))
        #expect(mapped(401, Fixture.unauthorizedKnown).message == "This iPhone isn't on Enchiridion's list yet.")
    }

    @Test func unauthorizedWithoutDevice() {
        #expect(mapped(401, Fixture.unauthorizedUnknown) == .unauthorized(device: nil))
        #expect(mapped(401, "") == .unauthorized(device: nil))
        #expect(mapped(401, "").message == "Enchiridion couldn't tell which device this is. Is Tailscale on?")
    }

    @Test func forbiddenAndRestarting() {
        #expect(mapped(403, "") == .forbidden)
        #expect(mapped(502, "<html>Bad Gateway</html>") == .restarting)
    }

    @Test func notFoundIsPlainText() {
        let error = EnchiridionError.fromResponse(response(404), body: Data("Record with id 99999999 not found".utf8))
        #expect(error == .notFound)
        #expect(error.message == "That record couldn't be found.")
    }

    @Test func serverMessage() {
        #expect(mapped(500, #"{"message":"sourceId and targetId cannot be identical"}"#)
            == .server(status: 500, message: "sourceId and targetId cannot be identical"))
        let zod = mapped(500, Fixture.zodError)
        guard case .server(500, let message) = zod else {
            Issue.record("expected .server, got \(zod)")
            return
        }
        #expect(message.hasPrefix("[\n  {\n    \"expected\": \"number\""))
        #expect(!zod.isTransient)
    }

    @Test func searchErrorsUseAnErrorString() {
        #expect(mapped(400, #"{"error":"Missing query parameter \"q\""}"#)
            == .rejected(status: 400, message: #"Missing query parameter "q""#))
        #expect(mapped(503, #"{"error":"Embeddings are not configured (set OPENAI_API_KEY)"}"#)
            == .server(status: 503, message: "Embeddings are not configured (set OPENAI_API_KEY)"))
    }

    @Test func authBodyShapeOnOtherStatuses() {
        #expect(mapped(409, #"{"error":{"code":"conflict","message":"Record 4 is already being archived"}}"#)
            == .rejected(status: 409, message: "Record 4 is already being archived"))
        #expect(ErrorBody.decode(Data(Fixture.unauthorizedKnown.utf8))?.code == "unauthorized")
    }

    @Test func bodiesWithoutAMessage() {
        #expect(mapped(500, "") == .server(status: 500, message: "Enchiridion ran into a problem."))
        #expect(mapped(500, "<!DOCTYPE html><html>Internal error</html>")
            == .server(status: 500, message: "Enchiridion ran into a problem."))
        #expect(mapped(500, "{}") == .server(status: 500, message: "Enchiridion ran into a problem."))
        #expect(mapped(422, #"{"message":"   "}"#) == .rejected(status: 422, message: "Enchiridion couldn't accept that request."))
        #expect(mapped(400, "Record with id 4 has no URL to archive")
            == .rejected(status: 400, message: "Record with id 4 has no URL to archive"))
    }

    @Test func longServerMessagesAreCut() {
        let long = String(repeating: "x", count: 1_000)
        let error = mapped(500, #"{"message":"\#(long)"}"#)
        #expect(error.message.count == 250)
        #expect(EnchiridionError.rejected(status: 400, message: "short").message == "short")
    }

    @Test func transience() {
        let transient: [EnchiridionError] = [.tailscaleOff, .unreachable, .offline, .restarting]
        let permanent: [EnchiridionError] = [
            .unauthorized(device: nil), .forbidden, .notFound, .rejected(status: 400, message: ""),
            .server(status: 500, message: ""), .decoding(""),
        ]
        #expect(transient.allSatisfy { $0.isTransient })
        #expect(!permanent.contains { $0.isTransient })
    }

    @Test func messages() {
        #expect(EnchiridionError.tailscaleOff.message == "Tailscale is off. Turn it on to reach Enchiridion.")
        #expect(EnchiridionError.unreachable.message == "Can't reach voyager.")
        #expect(EnchiridionError.offline.message == "You're offline.")
        #expect(EnchiridionError.restarting.message == "Enchiridion is restarting.")
        #expect(EnchiridionError.forbidden.message == "voyager refused the connection. Is this device on the tailnet?")
        #expect(EnchiridionError.decoding("x").message == "Enchiridion sent something this app couldn't read.")
        #expect(EnchiridionError.offline.localizedDescription == "You're offline.")
    }
}
