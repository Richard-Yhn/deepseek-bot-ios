// DeepSeek Bot for iOS — Apache-2.0
// These tests pin the two things that break silently: how a pasted login URL is
// taken apart, and how the host's JSON is read. Fixtures are shaped from
// ds-bot/src/host/channel.js (state) and parts.js (chat items).

import XCTest
@testable import DeepSeekBot

@MainActor
final class DSBCoreTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Login URL

    func testFullLoginURLKeepsTokenAndDropsQuery() {
        let address = HostAddress.parse("http://192.168.1.5:3080/?token=abc123")
        XCTAssertEqual(address?.origin, "http://192.168.1.5:3080")
        XCTAssertEqual(address?.token, "abc123")
        XCTAssertEqual(address?.loginURL?.absoluteString, "http://192.168.1.5:3080?token=abc123")
    }

    func testBareHostGetsDefaultPort() {
        let address = HostAddress.parse("192.168.1.5")
        XCTAssertEqual(address?.origin, "http://192.168.1.5:3080")
        XCTAssertNil(address?.token)
    }

    func testHostAndPortAreKept() {
        let address = HostAddress.parse("10.0.0.7:13080")
        XCTAssertEqual(address?.origin, "http://10.0.0.7:13080")
        XCTAssertEqual(address?.displayHost, "10.0.0.7:13080")
    }

    func testSeparateTokenFieldIsUsed() {
        let address = HostAddress.parse("192.168.1.5:3080", token: "  fromfield  ")
        XCTAssertEqual(address?.token, "fromfield")
    }

    func testTokenInsideURLWins() {
        let address = HostAddress.parse("http://192.168.1.5:3080/?token=fromurl", token: "fromfield")
        XCTAssertEqual(address?.token, "fromurl")
    }

    func testEmptyInputIsRejected() {
        XCTAssertNil(HostAddress.parse("   "))
    }

    // MARK: - Times

    func testEpochMilliseconds() throws {
        let time = try decode(DSBTime.self, "1729531234567")
        let value = try XCTUnwrap(time.date)
        XCTAssertEqual(value.timeIntervalSince1970, 1_729_531_234.567, accuracy: 0.01)
    }

    func testEpochSeconds() throws {
        let time = try decode(DSBTime.self, "1729531234")
        let value = try XCTUnwrap(time.date)
        XCTAssertEqual(value.timeIntervalSince1970, 1_729_531_234, accuracy: 0.5)
    }

    func testISO8601() throws {
        let time = try decode(DSBTime.self, "\"2026-10-21T15:30:00Z\"")
        XCTAssertNotNil(time.date)
    }

    func testGarbageTimeIsNilButDoesNotThrow() throws {
        let time = try decode(DSBTime.self, "{\"weird\":true}")
        XCTAssertNil(time.date)
    }

    // MARK: - Envelopes

    func testKeyedListDecodesAsArray() throws {
        let list = try decode(FlexibleList<Approval>.self, """
        {"a":{"id":"1","tool":"bash"},"b":{"id":"2","tool":"edit"}}
        """)
        XCTAssertEqual(list.items.count, 2)
    }

    func testMalformedListDegradesToEmpty() throws {
        let list = try decode(FlexibleList<Approval>.self, "\"not a list\"")
        XCTAssertTrue(list.items.isEmpty)
    }

    // MARK: - Team state

    private let stateFixture = """
    {
      "revision": 42,
      "mainBotId": "b1",
      "mainBotIds": ["b1"],
      "bots": [
        {"id":"b1","name":"阿鲸","role":"主 Bot","color":"#4d6bfe","model":"deepseek-v4","sessionId":"s1","parts":["s0","s1"]},
        {"id":"b2","name":"小探","role":"检索","waiting":true}
      ],
      "rooms": [
        {"id":"r1","name":"周会","members":["b1","b2"],"preview":"阿鲸：早上好","mode":"round"}
      ],
      "work": {
        "bots": {"b1": {"tool": "bash"}},
        "approvals": [
          {"id":"a1","sessionId":"gs1","botId":"b1","roomId":"r1","tool":"bash","reason":"要删掉 build 目录","answerable":true,"at":1729531234567}
        ],
        "turns": {"b1": 1729531200000}
      },
      "models": [{"ref":"deepseek-chat","reasoning":true}],
      "readOnly": null
    }
    """

    func testTeamsBotsAndRooms() throws {
        let view = try decode(TeamView.self, stateFixture)
        XCTAssertEqual(view.botList.count, 2)
        XCTAssertEqual(view.roomList.count, 1)
        XCTAssertEqual(view.botList.first?.displayName, "阿鲸")
        XCTAssertTrue(view.isMain(view.botList[0]))
        XCTAssertFalse(view.isMain(view.botList[1]))
    }

    func testWorkingAndWaitingFlags() throws {
        let view = try decode(TeamView.self, stateFixture)
        XCTAssertTrue(view.isWorking(view.botList[0]))
        XCTAssertFalse(view.isWorking(view.botList[1]))
        XCTAssertEqual(view.botList[1].waiting, true)
    }

    func testApprovalIsReadableAndAnswerable() throws {
        let view = try decode(TeamView.self, stateFixture)
        let approval = try XCTUnwrap(view.approvalList.first)
        XCTAssertEqual(approval.id, "a1")
        XCTAssertEqual(approval.roomId, "r1")
        XCTAssertTrue(approval.title.contains("bash"))
        XCTAssertEqual(approval.detail, "要删掉 build 目录")
        XCTAssertNotNil(approval.at?.date)
    }

    func testUnknownFieldsAreIgnored() throws {
        let json = """
        {"revision": 1, "bots": [], "somethingNew": {"deep": [1,2,3]}, "readOnly": "另一台 dsh 占着"}
        """
        let view = try decode(TeamView.self, json)
        XCTAssertTrue(view.isReadOnly)
        XCTAssertTrue(view.botList.isEmpty)
    }

    // MARK: - A Bot's chat

    private let chatFixture = """
    {
      "sessionId": "s1",
      "items": [
        {"kind":"user","text":"帮我看看构建","time":1729531200000},
        {"kind":"bot","text":"好的","time":1729531205000},
        {"kind":"answer","answers":{"q1":["OK"]},"time":1729531210000},
        {"kind":"event","role":"request","name":"小探","time":1729531215000},
        {"kind":"divider","time":1729531220000}
      ],
      "cursor": {"part": 1, "beforeSeq": 120}
    }
    """

    func testChatKinds() throws {
        let page = try decode(ChatPage.self, chatFixture)
        XCTAssertEqual(page.lines.count, 5)
        XCTAssertEqual(page.lines.map(\.parsed), [.user, .bot, .answer, .event, .divider])
        XCTAssertEqual(page.lines[0].text, "帮我看看构建")
        XCTAssertEqual(page.cursor?.part, 1)
        XCTAssertEqual(page.cursor?.beforeSeq, 120)
    }

    func testAnswerAndEventPlaceholders() throws {
        let page = try decode(ChatPage.self, chatFixture)
        XCTAssertEqual(page.lines[2].placeholder, "（已作答）")
        XCTAssertTrue(page.lines[3].placeholder.contains("小探"))
    }

    func testLineIdentitySurvivesAPoll() throws {
        let first = TeamModel.stableLines(try decode(ChatPage.self, chatFixture).lines)
        let second = TeamModel.stableLines(try decode(ChatPage.self, chatFixture).lines)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testRepeatedTextKeepsDistinctRows() throws {
        let json = """
        {"items":[{"kind":"bot","text":"同样的"},{"kind":"bot","text":"同样的"}],"cursor":null}
        """
        let lines = TeamModel.stableLines(try decode(ChatPage.self, json).lines)
        XCTAssertEqual(lines.count, 2)
        XCTAssertNotEqual(lines[0].id, lines[1].id)
    }

    func testEmptyChatPage() throws {
        let page = try decode(ChatPage.self, "{\"sessionId\":\"s1\",\"items\":[],\"cursor\":null}")
        XCTAssertTrue(page.lines.isEmpty)
        XCTAssertNil(page.cursor)
    }
}
