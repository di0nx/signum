//
//  DERBuilderTests.swift
//  SignumKitTests
//

import XCTest
@testable import SignumKit

final class DERBuilderTests: XCTestCase {

    func testShortLength() {
        XCTAssertEqual(DERBuilder.derLength(0), Data([0x00]))
        XCTAssertEqual(DERBuilder.derLength(1), Data([0x01]))
        XCTAssertEqual(DERBuilder.derLength(127), Data([0x7F]))
    }

    func testLongLength() {
        XCTAssertEqual(DERBuilder.derLength(128), Data([0x81, 0x80]))
        XCTAssertEqual(DERBuilder.derLength(256), Data([0x82, 0x01, 0x00]))
        XCTAssertEqual(DERBuilder.derLength(65535), Data([0x82, 0xFF, 0xFF]))
    }

    func testSequence() {
        let content = Data([0x01, 0x02, 0x03])
        XCTAssertEqual(DERBuilder.derSequence(content), Data([0x30, 0x03, 0x01, 0x02, 0x03]))
    }

    func testSet() {
        let content = Data([0xAA])
        XCTAssertEqual(DERBuilder.derSet(content), Data([0x31, 0x01, 0xAA]))
    }

    func testIntegerSmall() {
        XCTAssertEqual(DERBuilder.derInteger(0), Data([0x02, 0x01, 0x00]))
        XCTAssertEqual(DERBuilder.derInteger(1), Data([0x02, 0x01, 0x01]))
        XCTAssertEqual(DERBuilder.derInteger(127), Data([0x02, 0x01, 0x7F]))
    }

    func testIntegerHighBitPadding() {
        // 128 has the high bit set, so a leading 0x00 must be prepended.
        XCTAssertEqual(DERBuilder.derInteger(128), Data([0x02, 0x02, 0x00, 0x80]))
        XCTAssertEqual(DERBuilder.derInteger(255), Data([0x02, 0x02, 0x00, 0xFF]))
        XCTAssertEqual(DERBuilder.derInteger(256), Data([0x02, 0x02, 0x01, 0x00]))
    }

    func testIntegerFromData() {
        XCTAssertEqual(DERBuilder.derInteger(Data([0x00, 0x00, 0x05])), Data([0x02, 0x01, 0x05]))
        XCTAssertEqual(DERBuilder.derInteger(Data([0x80])), Data([0x02, 0x02, 0x00, 0x80]))
        XCTAssertEqual(DERBuilder.derInteger(Data()), Data([0x02, 0x01, 0x00]))
    }

    func testOctetString() {
        XCTAssertEqual(DERBuilder.derOctetString(Data([0xDE, 0xAD])), Data([0x04, 0x02, 0xDE, 0xAD]))
    }

    func testBitString() {
        // A leading 0x00 unused-bits octet is prepended.
        XCTAssertEqual(DERBuilder.derBitString(Data([0xFF])), Data([0x03, 0x02, 0x00, 0xFF]))
    }

    func testBoolean() {
        XCTAssertEqual(DERBuilder.derBoolean(true), Data([0x01, 0x01, 0xFF]))
        XCTAssertEqual(DERBuilder.derBoolean(false), Data([0x01, 0x01, 0x00]))
    }

    func testNull() {
        XCTAssertEqual(DERBuilder.derNull(), Data([0x05, 0x00]))
    }

    func testOID() {
        XCTAssertEqual(
            DERBuilder.derOID(DERBuilder.sha256OIDBytes),
            Data([0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01])
        )
    }

    func testExplicitContextTags() {
        XCTAssertEqual(DERBuilder.derExplicitContext0(Data([0x01])), Data([0xA0, 0x01, 0x01]))
        XCTAssertEqual(DERBuilder.derExplicitContext1(Data([0x01])), Data([0xA1, 0x01, 0x01]))
    }

    func testTimeStampRequestStructure() {
        let digest = Data(repeating: 0xAB, count: 32)
        let request = DERBuilder.timeStampRequest(
            digest: digest,
            hashOIDBytes: DERBuilder.sha256OIDBytes,
            nonce: 0x0102030405060708,
            certReq: true
        )
        // Must be a SEQUENCE.
        XCTAssertEqual(request.first, 0x30)

        // Parse it back and sanity-check the top-level shape.
        let nodes = DERParser.parseSequence(request)
        XCTAssertEqual(nodes.count, 1)
        let top = try? XCTUnwrap(nodes.first)
        let fields = top?.children() ?? []
        // version, messageImprint, nonce, certReq
        XCTAssertEqual(fields.count, 4)
        XCTAssertEqual(DERParser.integer(fields[0]), 1)          // version == 1
        XCTAssertEqual(fields[3].tag, 0x01)                       // certReq BOOLEAN
        XCTAssertEqual(fields[3].content, Data([0xFF]))           // TRUE
    }

    func testTimeStampRequestEmbedsDigest() {
        let digest = Data(repeating: 0x11, count: 32)
        let request = DERBuilder.timeStampRequest(
            digest: digest,
            hashOIDBytes: DERBuilder.sha256OIDBytes,
            nonce: 42,
            certReq: false
        )
        // The digest should appear verbatim inside the OCTET STRING.
        XCTAssertTrue(request.range(of: digest) != nil)
    }
}
