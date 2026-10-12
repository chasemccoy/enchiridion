import EnchiridionKit
import Foundation
import Testing
@testable import EnchiridionCore

struct StatusTextTests {
    private let vern = Device(id: "ngfBN1QCot11CNTRL", name: "vern")

    @Test func signedIn() {
        #expect(StatusText.signedIn(Me(scheme: "tailscale", device: vern, user: "chase@github"))
            == "Signed in as vern through Tailscale")
        #expect(StatusText.signedIn(Me(scheme: "tailscale")) == "Signed in through Tailscale")
        #expect(StatusText.signedIn(Me(scheme: "local")) == "Signed in on this Mac")
        #expect(StatusText.signedIn(Me(scheme: "open")) == "Open: Enchiridion isn't checking devices")
        #expect(StatusText.signedIn(Me(scheme: "bearer")) == "Signed in through bearer")
    }

    @Test func problems() {
        #expect(StatusText.problem(.tailscaleOff) == "Tailscale is off")
        #expect(StatusText.problem(.offline) == "You're offline")
        #expect(StatusText.problem(.unreachable) == "Can't reach voyager")
        #expect(StatusText.problem(.restarting) == "Enchiridion is restarting")
        #expect(StatusText.problem(.unauthorized(device: vern)) == "Not on Enchiridion's list")
        #expect(StatusText.problem(.unauthorized(device: nil)) == "Can't tell which device this is")
        #expect(StatusText.problem(.server(status: 500, message: "x")) == "Couldn't check this device")
    }

    @Test func aFailureWinsOverAnOlderAnswer() {
        let me = Me(scheme: "local")
        #expect(StatusText.connection(me: me, error: .offline, checking: false) == "You're offline")
        #expect(StatusText.connection(me: me, error: nil, checking: true) == "Signed in on this Mac")
        #expect(StatusText.connection(me: nil, error: nil, checking: true) == "Checking…")
        #expect(StatusText.connection(me: nil, error: nil, checking: false) == nil)
    }
}

@MainActor
struct ConnectionModelTests {
    @Test func asksWhoThisDeviceIs() async throws {
        let transport = StubTransport { request in
            #expect(request.route == "GET /me")
            return .raw(#"{"scheme":"tailscale","device":{"id":"n1","name":"vern"},"user":"chase@github"}"#)
        }
        let connection = ConnectionModel(environment: .test(transport))
        #expect(connection.status == nil)
        #expect(connection.host == "enchiridion.example.test")

        await connection.refresh()
        #expect(connection.status == "Signed in as vern through Tailscale")
        #expect(connection.device == Device(id: "n1", name: "vern"))
        #expect(connection.me?.user == "chase@github")
        #expect(connection.checkedAt == Date(timeIntervalSince1970: 1_791_763_200))
        #expect(!connection.isNotAllowed)
    }

    @Test func aRefusedDeviceIsStillNamed() async {
        let transport = StubTransport { _ in
            .raw(#"{"scheme":"tailscale","device":{"id":"n1","name":"vern"},"user":null}"#)
        }
        let connection = ConnectionModel(environment: .test(transport))
        await connection.refresh()
        await transport.respond { _ in
            .raw(#"{"error":{"code":"unauthorized","message":"x"},"message":"x","device":{"id":"n1","name":"vern"}}"#,
                 status: 401)
        }
        await connection.refresh()
        #expect(connection.me == nil, "a 401 clears the old answer")
        #expect(connection.isNotAllowed)
        #expect(connection.device == Device(id: "n1", name: "vern"))
        #expect(connection.status == "Not on Enchiridion's list")
    }

    @Test func anOutageKeepsTheDevice() async {
        let transport = StubTransport { _ in .raw(#"{"scheme":"local","device":null,"user":null}"#) }
        let connection = ConnectionModel(environment: .test(transport))
        await connection.refresh()
        await transport.respond { _ in throw URLError(.cannotFindHost) }
        await connection.refresh()
        #expect(connection.me == Me(scheme: "local"))
        #expect(connection.lastError == .tailscaleOff)
        #expect(connection.status == "Tailscale is off")
    }
}

struct ServerTests {
    @Test func productionUnlessALaunchArgumentSaysOtherwise() {
        #expect(Server.production.absoluteString == "https://enchiridion-api.chsmc.tools")
        #expect(Server.fromArguments([]) == Server.production)
        #expect(Server.fromArguments(["-EnchiridionServer", "http://localhost:4321/records?x=1"])
            == URL(string: "http://localhost:4321"))
        #expect(Server.fromArguments(["-EnchiridionServer", "enchiridion.example.test"])
            == URL(string: "https://enchiridion.example.test"))
        let sandbox = URL(string: "http://localhost:4399")!
        #expect(Server.fromArguments([], fallback: sandbox) == sandbox)
    }

    @Test func anOverrideThatNamesNoServerNeverMeansProduction() {
        // Asked for another server, but not one this can reach: every request fails rather than writing to production.
        #expect(Server.misconfigured.host() == "enchiridion-server-misconfigured.invalid")
        #expect(Server.fromArguments(["-EnchiridionServer", "ftp://example.com"]) == Server.misconfigured)
        #expect(Server.fromArguments(["-EnchiridionServer", "http:"]) == Server.misconfigured)
        #expect(Server.fromArguments(["-EnchiridionServer", ""]) == Server.misconfigured)
        #expect(Server.fromArguments(["-EnchiridionServer"]) == Server.misconfigured)
        let sandbox = URL(string: "http://localhost:4399")!
        #expect(Server.fromArguments(["-EnchiridionServer", "not a server"], fallback: sandbox) == Server.misconfigured)
        // `ENCHIRIDION_SERVER = http://localhost:4399` in Local.xcconfig reaches the Info.plist as "http:".
        for value: Any in ["http:", "https:", "ftp://example.com", "htp://localhost:4399", "not a server", 4399] {
            #expect(Server.fromInfoValue(value) == Server.misconfigured, "\(value)")
        }
        #expect(Server.displayHost(Server.misconfigured) == "enchiridion-server-misconfigured.invalid")
    }

    @Test func aDebugBuildMayNameAServerInItsInfoPlist() {
        // `ENCHIRIDION_SERVER = http:/$()/localhost:4399` in Local.xcconfig (`//` would start a comment there).
        #expect(Server.fromInfoValue("http://localhost:4399") == URL(string: "http://localhost:4399"))
        #expect(Server.fromInfoValue("enchiridion.example.test") == URL(string: "https://enchiridion.example.test"))
        #expect(Server.fromInfoValue("") == nil, "the default: unset")
        #expect(Server.fromInfoValue("$(ENCHIRIDION_SERVER)") == nil, "unexpanded")
        #expect(Server.fromInfoValue("  ") == nil, "blank: unset")
        #expect(Server.fromInfoValue(nil) == nil)
        #expect(Server.fromInfoDictionary(.main) == nil, "the test runner's bundle names none")
    }

    @Test func displayHost() {
        #expect(Server.displayHost(Server.production) == "enchiridion-api.chsmc.tools")
        #expect(Server.displayHost(URL(string: "http://localhost:4321")!) == "localhost:4321")
    }

    @Test func clientsIdentifyTheirRole() async throws {
        let transport = StubTransport { _ in .raw(#"{"name":"enchiridion","auth":[]}"#) }
        let environment = AppEnvironment.test(transport)
        _ = try await environment.client(role: .share).info()
        let request = try #require(await transport.requests.last)
        #expect(request.headers["X-Enchiridion-Client"] == "ios/0.1 share")
        #expect(request.route == "GET /info")
    }
}
