// DeepSeek Bot for iOS — Apache-2.0
// The whole client channel of ds-bot is one Fetch route:
//
//   POST <origin>/api/bot
//   { "endpoint": "state", "payload": { … } }
//   → { "ok": true,  "value": … }
//   → { "ok": false, "error": { "code": "bot/…", "message": "…" } }
//
// The browser client authenticates with its session cookie (ds-bot/src/client/api.js).
// This client does the same thing with URLSession, so nothing about the host changes.

import Foundation

@MainActor
final class DSBClient {
    private let session: URLSession
    private(set) var address: HostAddress?
    private(set) var lastResponseAt: Date?

    private static let route = "api/bot"

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = .shared
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    var isConnected: Bool { address != nil }

    // MARK: - Connect

    /// Trades the token for the host's cookie, then proves the channel with `state`.
    func connect(to candidate: HostAddress) async throws -> TeamView {
        guard let login = candidate.loginURL, candidate.baseURL != nil else {
            throw DSBError.badAddress(candidate.origin)
        }

        // 1. The login URL sets the signed cookie. Its body is not needed.
        var loginRequest = URLRequest(url: login)
        loginRequest.httpMethod = "GET"
        loginRequest.timeoutInterval = 20
        _ = try? await session.data(for: loginRequest)

        // 2. `state` is the channel's handshake: it is what the web UI asks for first.
        address = candidate
        do {
            return try await call("state", ["locale": "zh-CN"], as: TeamView.self)
        } catch {
            address = nil
            throw error
        }
    }

    func disconnect() {
        address = nil
        lastResponseAt = nil
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies { HTTPCookieStorage.shared.deleteCookie(cookie) }
        }
    }

    // MARK: - Calls

    func call<T: Decodable>(_ endpoint: String, _ payload: [String: Any] = [:], as type: T.Type) async throws -> T {
        let data = try await raw(endpoint, payload)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DSBError.malformed("\(endpoint): \(error)")
        }
    }

    @discardableResult
    func callVoid(_ endpoint: String, _ payload: [String: Any] = [:]) async throws -> Bool {
        _ = try await raw(endpoint, payload)
        return true
    }

    private func raw(_ endpoint: String, _ payload: [String: Any]) async throws -> Data {
        guard let address, let origin = address.baseURL else { throw DSBError.notConnected }

        var request = URLRequest(url: origin.appendingPathComponent(Self.route))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "endpoint": endpoint,
            "payload": payload.isEmpty ? NSNull() : payload,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DSBError.malformed("网络错误：\(error.localizedDescription)")
        }
        lastResponseAt = Date()

        guard let http = response as? HTTPURLResponse else { throw DSBError.malformed("不是 HTTP 响应") }
        guard http.statusCode == 200 else { throw DSBError.http(http.statusCode) }

        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DSBError.malformed("响应不是 JSON 对象")
        }
        guard (object["ok"] as? Bool) == true else {
            let failure = object["error"] as? [String: Any]
            throw DSBError.refused(
                code: failure?["code"] as? String ?? "bot/error",
                message: failure?["message"] as? String ?? "请求失败"
            )
        }
        let value = object["value"] ?? NSNull()
        return try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    }
}
