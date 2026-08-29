import Foundation
import MikroTikKit

func runRouterValueTests() {
    suite("RouterValue decoding") {
        test("decodes string, number, boolean and null scalars") {
            // Arrange
            let json = #"{"name":"WAN1","mtu":1500,"running":true,"comment":null}"#

            // Act
            let record = try Fixture.record(json)

            // Assert
            assertEqual(record["name"], .string("WAN1"))
            assertEqual(record["mtu"], .number(1500))
            assertEqual(record["running"], .bool(true))
            assertEqual(record["comment"], .null)
        }

        test("numeric scalars render without a fractional part") {
            assertEqual(RouterValue.number(1500).stringValue, "1500")
            assertEqual(RouterValue.number(1.5).stringValue, "1.5")
            assertEqual(RouterValue.bool(false).stringValue, "false")
            assertNil(RouterValue.null.stringValue)
        }

        test("string accessor treats empty values as missing") {
            let record = try Fixture.record(#"{"name":"","comment":"hi"}"#)

            assertNil(record.string("name"))
            assertEqual(record.string("comment"), "hi")
            assertNil(record.string("absent"))
        }

        test("uint64 accessor handles string and numeric counters") {
            let record = try Fixture.record(
                #"{"a":"18446744073709551615","b":4096,"c":"-5","d":"nope"}"#
            )

            assertEqual(record.uint64("a"), UInt64.max)
            assertEqual(record.uint64("b"), 4096)
            assertNil(record.uint64("c"), "negative counters are rejected")
            assertNil(record.uint64("d"))
        }

        test("flag accepts every RouterOS boolean spelling") {
            let record = try Fixture.record(
                #"{"a":"true","b":"no","c":"1","d":true,"e":"maybe"}"#
            )

            assertTrue(record.flag("a"))
            assertFalse(record.flag("b"))
            assertTrue(record.flag("c"))
            assertTrue(record.flag("d"))
            // Unparseable values fall back instead of silently reading as false.
            assertTrue(record.flag("e", default: true))
            assertTrue(record.flag("missing", default: true))
            assertFalse(record.flag("missing"))
        }
    }
}
