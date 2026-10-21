// DeepSeek Bot for iOS — Apache-2.0
// A minimal streaming client for OpenAI-compatible endpoints: one POST to
// `<baseURL>/chat/completions` with `stream: true`, then `data:` lines until `[DONE]`.
//
// Deliberately not a general SDK — it sends what a direct chat needs and nothing else,
// so the phone can compute without pulling a dependency into an unreviewed build.
//
// `@MainActor` on the one entry point is the point: the delta callback may touch view
// state directly, because the whole call already runs on the main actor.

import Foundation

enum DirectModel {
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 600
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// Streams the assistant text into `onDelta`, one fragment at a time. Returns when
    /// the model finishes or the connection closes.
    @MainActor
    static func stream(
        config: DirectConfig,
        history: [DirectMessage],
        onDelta: (String) -> Void
    ) async throws {
        guard let url = config.endpoint else { throw DSBError.badAddress(config.baseURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        var wire: [[String: String]] = []
        let system = config.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            wire.append(["role": "system", "content": system])
        }
        for message in history {
            wire.append(["role": message.role, "content": message.text])
        }
        let body: [String: Any] = [
            "model": config.model.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": wire,
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = makeSession()
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw DSBError.malformed("连不上这个接口：\(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw DSBError.malformed("不是 HTTP 响应")
        }
        guard http.statusCode == 200 else {
            throw DSBError.http(http.statusCode)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            if let failure = object["error"] as? [String: Any] {
                let message = failure["message"] as? String ?? "接口报错"
                throw DSBError.refused(code: "direct/error", message: message)
            }
            guard let choices = object["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any]
            else { continue }
            if let content = delta["content"] as? String, !content.isEmpty {
                onDelta(content)
            }
        }
    }
}
