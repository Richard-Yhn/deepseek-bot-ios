// DeepSeek Bot for iOS — Apache-2.0
//
// The host is free to reshape a field; this client must not lose the team over it.
// These cases exist because it did: `bots[].avatar` is `{"shape": "whale"}`, the model
// declared `String?`, and the whole `state` answer failed with
//   DecodingError.typeMismatch ... Path: bots[0].avatar
// which the app showed as "宿主返回的内容无法解析" instead of the Bot list.

import XCTest
@testable import DeepSeekBot

@MainActor
final class DSBToleranceTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - avatar

    func testAvatarIsAnObject() throws {
        let bot = try decode(Bot.self, """
        {"id":"b1","name":"阿鲸","avatar":{"shape":"whale"}}
        """)
        XCTAssertEqual(bot.avatar?.shape, "whale")
        XCTAssertNil(bot.avatar?.image)
        XCTAssertEqual(bot.name, "阿鲸")
    }

    func testAvatarCarriesAnImageToo() throws {
        let bot = try decode(Bot.self, """
        {"id":"b1","avatar":{"shape":"whale","image":"data:image/png;base64,AA"}}
        """)
        XCTAssertEqual(bot.avatar?.shape, "whale")
        XCTAssertEqual(bot.avatar?.image, "data:image/png;base64,AA")
    }

    func testAvatarAsAPlainStringStillDecodes() throws {
        let bot = try decode(Bot.self, #"{"id":"b1","avatar":"whale"}"#)
        XCTAssertEqual(bot.avatar?.shape, "whale")
    }

    func testAvatarInAnUnknownShapeCostsOnlyTheAvatar() throws {
        let bot = try decode(Bot.self, #"{"id":"b1","name":"阿鲸","avatar":42}"#)
        XCTAssertNil(bot.avatar)
        XCTAssertEqual(bot.name, "阿鲸")
    }

    // MARK: - the team survives odd fields

    func testOneOddBotDoesNotBreakTheTeam() throws {
        let view = try decode(TeamView.self, """
        {"revision":7,"bots":[
          {"id":"b1","name":"阿鲸","avatar":{"shape":"whale"}},
          {"id":"b2","name":"小探","parts":"not an array","waiting":"maybe"}
        ],"rooms":[{"id":"r1","name":"周会","members":[{"id":"b1"}]}]}
        """)
        XCTAssertEqual(view.botList.count, 2)
        XCTAssertEqual(view.botList[0].avatar?.shape, "whale")
        XCTAssertEqual(view.botList[1].name, "小探")
        XCTAssertNil(view.botList[1].parts)
        XCTAssertNil(view.botList[1].waiting)
        XCTAssertEqual(view.roomList.count, 1)
        XCTAssertNil(view.roomList[0].members)
    }

    func testModelCatalogSurvivesAnOddEntry() throws {
        let view = try decode(TeamView.self, """
        {"bots":[],"models":[{"ref":"deepseek/chat"},{"ref":42}],"defaultModel":"deepseek/chat"}
        """)
        XCTAssertEqual(view.modelList.count, 2)
        XCTAssertEqual(view.modelList[0].ref, "deepseek/chat")
        XCTAssertNil(view.modelList[1].ref)
        XCTAssertEqual(view.defaultModel, "deepseek/chat")
    }

    func testApprovalSurvivesAnOddField() throws {
        let view = try decode(TeamView.self, """
        {"bots":[],"work":{"approvals":[{"id":"a1","tool":"bash","at":"2026-10-22T00:00:00Z","answerable":"yes"}]}}
        """)
        let approval = try XCTUnwrap(view.approvalList.first)
        XCTAssertEqual(approval.id, "a1")
        XCTAssertEqual(approval.tool, "bash")
        XCTAssertNil(approval.answerable)
        XCTAssertNotNil(approval.at?.date)
    }

    // MARK: - the token people actually paste

    func testTokenPastedAsAQueryFragment() {
        let address = HostAddress.parse("192.168.1.96:3080", token: "?token=b9jU&x=1")
        XCTAssertEqual(address?.token, "b9jU")
        XCTAssertEqual(address?.loginURL?.absoluteString, "http://192.168.1.96:3080?token=b9jU")
    }

    func testTokenWithQuotesAndSpaces() {
        XCTAssertEqual(HostAddress.normalizeToken("  \"token=abc\"  "), "abc")
        XCTAssertEqual(HostAddress.normalizeToken("&token=abc"), "abc")
        XCTAssertEqual(HostAddress.normalizeToken("abc"), "abc")
        XCTAssertNil(HostAddress.normalizeToken("   "))
    }
}
