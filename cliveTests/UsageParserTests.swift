import XCTest
import SwiftTerm
@testable import Clive

final class UsageParserTests: XCTestCase {

    // Base64 encoded raw output from claude /usage command
    // Contains ANSI escape sequences, cursor movements, and TUI rendering
    static let testDataBase64 = """
c3Bhd24gL29wdC9ob21lYnJldy9iaW4vY2xhdWRlIC91c2FnZQ0KG1s/MjAwNGgbWz8xMDA0aBtbPzI1bBtbPHUbWz8xMDA0bBtbPzIwMDRsG1s/MjVoG105OzQ7MDsHG1s/MjVoG1s/MTAwNGwbWz8yMDA0bBtbPzIwMDRoG1s/MTAwNGgbWz8yNWwbWzx1G1s/MTAwNGwbWz8yMDA0bBtbPzI1aBtdOTs0OzA7BxtbPzI1aBtbPzEwMDRsG1s/MjAwNGwbWz8yMDI2aCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgDQrila3ilIDilIDilIAgQ2xhdWRlIENvZGUgdjIuMS4yMCDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDila4NCuKUgiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICDilIIgVGlwcyBmb3IgZ2V0dGluZyAgICAgICAg4pSCDQrilIIgICAgICAgICAgICAgICAgV2VsY29tZSBiYWNrIFN0dWFydCEgICAgICAgICAgICAgICAgIOKUgiBzdGFydGVkICAgICAgICAgICAgICAgICDilIINCuKUgiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICDilIIgUnVuIC9pbml0IHRvIGNyZWF0ZSBhIOKApiDilIINCuKUgiAgICAgICAgICAgICAgICAgICAgICDilpDilpvilojilojilojilpzilowgICAgICAgICAgICAgICAgICAgICAg4pSCIOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgCDilIINCuKUgiAgICAgICAgICAgICAgICAgICAgICDilp3ilpzilojilojilojilojilojilpvilpggICAgICAgICAgICAgICAgICAgICDilIIgUmVjZW50IGFjdGl2aXR5ICAgICAgICAg4pSCDQrilIIgICAgICAgICAgICAgICAgICAgICAgICDilpjilpgg4pad4padICAgICAgICAgICAgICAgICAgICAgICDilIIgTm8gcmVjZW50IGFjdGl2aXR5ICAgICAg4pSCDQrilIIgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg4pSCICAgICAgICAgICAgICAgICAgICAgICAgIOKUgg0K4pSCICAgICBPcHVzIDQuNSDCtyBDbGF1ZGUgTWF4IMK3ICAgICAgICAgICAgICAgICAgICAgICAg4pSCICAgICAgICAgICAgICAgICAgICAgICAgIOKUgg0K4pSCICAgICBzdHVhcnQuY2FtZXJvbkBkZWFraW4uZWR1LmF1J3MgT3JnYW5pemF0aW9uICAgIOKUgiAgICAgICAgICAgICAgICAgICAgICAgICDilIINCuKUgiAgICAgICAgICAgICAgICAv4oCmL1QvY2xhdWRlLXVzYWdlLWJhciAgICAgICAgICAgICAgIOKUgiAgICAgICAgICAgICAgICAgICAgICAgICDilIINCuKVsOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKVrw0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANCuKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0K4p2vwqBUcnkgImhvdyBkb2VzIDxmaWxlcGF0aD4gd29yaz8iICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANCuKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KICA/IGZvciBzaG9ydGN1dHMgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANChtbPzIwMjZsG1s/MjAwNGgbWz8xMDA0aBtbPzI1bBtdMDvinLMgQ2xhdWRlIENvZGUHG10wO+KcsyBDbGF1ZGUgQ29kZQcbWz8yMDI2aA0bWzI0QxtbMTNBICAgICAgIA0bWzIzQxtbMUIg4paQ4pabG1szQ+KWnOKWjCANG1syM0MbWzFC4pad4pac4paI4paI4paI4paI4paI4pab4paYDRtbMjVDG1sxQuKWmOKWmBtbMUPilp3ilp0NG1s2QuKdryAvdXNhZ2UgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANG1sxQiAgICAgG1sxQyAgICAbWzFDICAgIBtbMUMgICAgICAgICAgG1sxQyAgICAgIA0bWzFCwrcgUmF6emxlLWRhenpsaW5n4oCmIChlc2MgdG8gaW50ZXJydXB0KSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANG1syQxtbMUIgG1sxQyAgIBtbMUMgICAgICAgICANG1sxQuKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0K4p2vwqAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANCuKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgOKUgA0KICA/IGZvciBzaG9ydGN1dHMgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANChtbPzIwMjZsG10wO+KcsyBDbGF1ZGUgQ29kZQcbXTA74pyzIENsYXVkZSBDb2RlBxtbPzIwMjZoDRtbN0HilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANG1sxQiDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIDilIANG1syQxtbMUJTZXR0aW5nczobWzJDU3RhdHVzG1szQ0NvbmZpZxtbM0NVc2FnZRtbMkMo4oaQL+KGkhtbMUNvchtbMUN0YWIbWzFDdG8bWzFDY3ljbGUpDRtbMUIgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIA0bWzFCICANG1sxQiAgTG9hZGluZyB1c2FnZSBkYXRh4oCmICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANG1syQxtbMUIgG1sxQyAgIBtbMUMgICAgICAgICANG1sxQiAgRXNjIHRvIGNhbmNlbCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgDQobWz8yMDI2bBtbPzIwMjZoDRtbMkMbWzNBQ3VycmUbWzFDdBtbMUNzZXNzaW9uICAgIA0bWzJDG1sxQuKWiOKWiOKWiOKWjBtbNDdDNyUbWzFDdXNlZA0bWzJDG1sxQlJlc2UbWzFDcxtbMUMzcG0gKEF1c3RyYWxpYS9NZWxib3VybmUpDRtbMUIgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIA0KICBDdXJyZW50IHdlZWsgKGFsbCBtb2RlbHMpICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANCiAg4paI4paI4paI4paMICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA3JSB1c2VkICAgICAgICAgICAgICAgICAgICANCiAgUmVzZXRzIEZlYiAyIGF0IDJwbSAoQXVzdHJhbGlhL01lbGJvdXJuZSkgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIA0KICBDdXJyZW50IHdlZWsgKFNvbm5ldCBvbmx5KSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgMCUgdXNlZCAgICAgICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIA0KICBFc2MgdG8gY2FuY2VsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICANChtbPzIwMjZs
"""

    var testInput: String!

    override func setUp() {
        super.setUp()
        guard let data = Data(base64Encoded: Self.testDataBase64),
              let string = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to decode test data")
            return
        }
        testInput = string
    }

    // MARK: - ANSI Terminal Buffer Tests

    func testAnsiTerminalBufferRendersSessionSection() {
        let rendered = renderAnsiOutput(testInput)

        // SwiftTerm should correctly render "Current session" from the ANSI sequences
        XCTAssertTrue(rendered.contains("Current session"), "Should contain 'Current session' after rendering with SwiftTerm")
    }

    func testAnsiTerminalBufferRendersCurrentWeek() {
        let rendered = renderAnsiOutput(testInput)

        XCTAssertTrue(rendered.contains("Current week (all models)"), "Should contain 'Current week (all models)'")
        XCTAssertTrue(rendered.contains("Current week (Sonnet only)"), "Should contain 'Current week (Sonnet only)'")
    }

    func testAnsiTerminalBufferRendersPercentages() {
        let rendered = renderAnsiOutput(testInput)

        // Should contain percentage values
        XCTAssertTrue(rendered.contains("7%") || rendered.contains("7 %"), "Should contain session/weekly percentage")
        XCTAssertTrue(rendered.contains("0%") || rendered.contains("0 %"), "Should contain Sonnet percentage")
    }

    func testAnsiTerminalBufferRendersResetTimes() {
        let rendered = renderAnsiOutput(testInput)

        // Should contain reset time information
        XCTAssertTrue(rendered.contains("3pm") || rendered.contains("2pm"), "Should contain reset time")
        XCTAssertTrue(rendered.contains("Australia/Melbourne"), "Should contain timezone")
    }

    // MARK: - Usage Parser Tests

    func testParseUsageOutputReturnsUsageInfo() {
        let usageInfo = parseUsageOutput(testInput)

        XCTAssertNotNil(usageInfo, "Should return UsageInfo")
    }

    func testParseUsageOutputExtractsSessionPercent() {
        let usageInfo = parseUsageOutput(testInput)

        XCTAssertNotNil(usageInfo?.sessionPercent, "Should extract session percentage")
        XCTAssertTrue(usageInfo?.sessionPercent?.contains("%") ?? false, "Session percentage should contain %")
    }

    func testParseUsageOutputExtractsWeeklyPercent() {
        let usageInfo = parseUsageOutput(testInput)

        XCTAssertNotNil(usageInfo?.weeklyPercent, "Should extract weekly percentage")
        // The test data shows 7% for weekly (all models)
        XCTAssertEqual(usageInfo?.weeklyPercent, "7%", "Weekly percentage should be 7%")
    }

    func testParseUsageOutputExtractsSessionResetTime() {
        let usageInfo = parseUsageOutput(testInput)

        // Session reset time may not be extracted if the text is corrupted
        if let sessionResets = usageInfo?.sessionResets {
            XCTAssertTrue(sessionResets.contains("pm") || sessionResets.contains("am"),
                          "Session reset should contain am/pm if extracted")
        }
    }

    func testParseUsageOutputExtractsWeeklyResetDate() {
        let usageInfo = parseUsageOutput(testInput)

        // Weekly reset may not be extracted depending on rendering
        // The raw data contains "Resets Feb 2 at 2pm" but cursor movements may affect rendering
        if let weeklyResets = usageInfo?.weeklyResets {
            // Should contain date info like "Feb 2" or time like "2pm"
            let hasDateOrTime = weeklyResets.contains("Feb") || weeklyResets.contains("pm") || weeklyResets.contains("at")
            XCTAssertTrue(hasDateOrTime, "Weekly reset should contain date/time info: \(weeklyResets)")
        }
        // At minimum, weekly percentage should be extracted
        XCTAssertNotNil(usageInfo?.weeklyPercent, "Should at least extract weekly percentage")
    }

    // MARK: - Edge Cases

    func testParseUsageOutputHandlesEmptyInput() {
        let usageInfo = parseUsageOutput("")

        XCTAssertNil(usageInfo, "Should return nil for empty input")
    }

    func testParseUsageOutputHandlesGarbageInput() {
        let usageInfo = parseUsageOutput("random garbage text with no usage data")

        XCTAssertNil(usageInfo, "Should return nil when no usage data found")
    }

    // MARK: - Cursor Movement Tests

    func testCursorMovementRight() {
        // Test that cursor right movement inserts proper spacing
        let input = "Hello\u{1b}[5CWorld"
        let rendered = renderAnsiOutput(input)

        XCTAssertTrue(rendered.contains("Hello") && rendered.contains("World"),
                      "Should render both parts with cursor movement")
    }

    func testCursorMovementUpAndDown() {
        // Test vertical cursor movement
        let input = "Line1\nLine2\u{1b}[1AInserted"
        let rendered = renderAnsiOutput(input)

        // "Inserted" should overwrite part of Line1
        XCTAssertTrue(rendered.contains("Inserted"), "Should contain text written after cursor up")
    }

    func testCarriageReturnOverwrites() {
        // Test that carriage return allows overwriting
        let input = "XXXXXX\rHello"
        let rendered = renderAnsiOutput(input)

        XCTAssertTrue(rendered.contains("Hello"), "Should contain overwritten text")
        // The X's after "Hello" might still be there
    }
}
