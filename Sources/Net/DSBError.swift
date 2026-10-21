// DeepSeek Bot for iOS — Apache-2.0
// Transport errors, worded the way the host words its own refusals.

import Foundation

enum DSBError: LocalizedError, Equatable {
    case badAddress(String)
    case notConnected
    case http(Int)
    case refused(code: String, message: String)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .badAddress(let text):
            return "地址无法识别：\(text)"
        case .notConnected:
            return "还没有连接到宿主。"
        case .http(let status):
            if status == 401 || status == 403 {
                return "宿主拒绝了这个令牌（HTTP \(status)）。请在宿主上重新取一个带 token 的登录地址。"
            }
            return "宿主返回 HTTP \(status)。"
        case .refused(let code, let message):
            return message.isEmpty ? "宿主拒绝了请求（\(code)）" : "\(message)"
        case .malformed(let detail):
            return "宿主返回的内容无法解析：\(detail)"
        }
    }
}
