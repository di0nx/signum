//
//  SignumKitTests.swift
//  SignumKitTests
//

import XCTest
@testable import SignumKit

final class DERParserTests: XCTestCase {

    func testParseNestedSequence() {
        // SEQUENCE { INTEGER 1, OCTET STRING [0xAA] }
        let der = DERBuilder.derSequence(DERBuilder.derInteger(1) + DERBuilder.derOctetString(Data([0xAA])))
        let nodes = DERParser.parseSequence(der)
        XCTAssertEqual(nodes.count, 1)
        let children = nodes[0].children()
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(DERParser.integer(children[0]), 1)
        XCTAssertEqual(children[1].content, Data([0xAA]))
    }

    func testEncodedRoundTrips() {
        let inner = DERBuilder.derInteger(258)
        let der = DERBuilder.derSequence(inner)
        let node = DERParser.parseSequence(der)[0]
        XCTAssertEqual(node.children().first?.encoded, inner)
    }

    func testGeneralizedTimeParsing() {
        let content = Data("20250629143219Z".utf8)
        let date = DERParser.generalizedTime(content)
        XCTAssertNotNil(date)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date!)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 6)
        XCTAssertEqual(comps.day, 29)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 32)
        XCTAssertEqual(comps.second, 19)
    }
}

final class FileHasherTests: XCTestCase {

    func testSHA256OfKnownContent() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let digest = try await FileHasher().sha256(fileURL: tmp)
        // Known SHA-256("abc").
        XCTAssertEqual(digest.hexString, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
