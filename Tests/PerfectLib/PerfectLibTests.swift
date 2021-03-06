//
//  PerfectLibTests.swift
//  PerfectLibTests
//
//  Created by Kyle Jessup on 2015-10-19.
//  Copyright © 2015 PerfectlySoft. All rights reserved.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//


import XCTest
import PerfectNet
import PerfectThread
@testable import PerfectLib

#if os(Linux)
import SwiftGlibc
import Foundation
#endif

class PerfectLibTests: XCTestCase {

	override func setUp() {
		super.setUp()
	#if os(Linux)
		SwiftGlibc.srand(UInt32(time(nil)))
	#endif
		// Put setup code here. This method is called before the invocation of each test method in the class.
		NetEvent.initialize()
	}

	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}



	func testConcurrentQueue() {
		let q = Threading.getQueue(name: "concurrent", type: .concurrent)

		var t1 = 0, t2 = 0, t3 = 0

		q.dispatch {
			t1 = 1
			Threading.sleep(seconds: 5)
		}
		q.dispatch {
			t2 = 1
			Threading.sleep(seconds: 5)
		}
		q.dispatch {
			t3 = 1
			Threading.sleep(seconds: 5)
		}
		Threading.sleep(seconds: 1)

		XCTAssert(t1 == 1 && t2 == 1 && t3 == 1)
	}

	func testSerialQueue() {
		let q = Threading.getQueue(name: "serial", type: .serial)

		var t1 = 0

		q.dispatch {
			XCTAssert(t1 == 0)
			t1 = 1
		}
		q.dispatch {
			XCTAssert(t1 == 1)
			t1 = 2
		}
		q.dispatch {
			XCTAssert(t1 == 2)
			t1 = 3
		}
		Threading.sleep(seconds: 2)
		XCTAssert(t1 == 3)
	}

	func testJSONConvertibleObject() {

		class Test: JSONConvertibleObject {

			static let registerName = "test"

			var one = 0
			override func setJSONValues(_ values: [String : Any]) {
				self.one = getJSONValue(named: "One", from: values, defaultValue: 42)
			}
			override func getJSONValues() -> [String : Any] {
				return [JSONDecoding.objectIdentifierKey:Test.registerName, "One":1]
			}
		}

		JSONDecoding.registerJSONDecodable(name: Test.registerName, creator: { return Test() })

		do {
			let encoded = try Test().jsonEncodedString()
			let decoded = try encoded.jsonDecode() as? Test

			XCTAssert(decoded != nil)

			XCTAssert(decoded!.one == 1)
		} catch {
			XCTAssert(false, "Exception \(error)")
		}
	}

	func testJSONEncodeDecode() {

		let srcAry: [[String:Any]] = [["i": -41451, "i2": 41451, "d": -42E+2, "t": true, "f": false, "n": nil as String?, "a":[1, 2, 3, 4]], ["another":"one"]]
		var encoded = ""
		var decoded: [Any]?
		do {

			encoded = try srcAry.jsonEncodedString()

		} catch let e {
			XCTAssert(false, "Exception while encoding JSON \(e)")
			return
		}

		do {

			decoded = try encoded.jsonDecode() as? [Any]

		} catch let e {
			XCTAssert(false, "Exception while decoding JSON \(e)")
			return
		}

		XCTAssert(decoded != nil)

		let resAry = decoded!

		XCTAssert(srcAry.count == resAry.count)

		for index in 0..<srcAry.count {

			let d1 = srcAry[index]
			let d2 = resAry[index] as? [String:Any]

			for (key, value) in d1 {

				let value2 = d2![key]

				XCTAssert(value2 != nil)

				switch value {
				case let i as Int:
					XCTAssert(i == value2 as! Int)
				case let d as Double:
					XCTAssert(d == value2 as! Double)
				case let s as String:
					XCTAssert(s == value2 as! String)
				case let s as Bool:
					XCTAssert(s == value2 as! Bool)

				default:
					()
					// does not go on to test sub-sub-elements
				}
			}

		}
	}

	func testJSONDecodeUnicode() {
		var decoded: [String: Any]?
		let jsonStr = "{\"emoji\": \"\\ud83d\\ude33\"}"     // {"emoji": "\ud83d\ude33"}
		do {
			decoded = try jsonStr.jsonDecode() as? [String: Any]
		} catch let e {

			XCTAssert(false, "Exception while decoding JSON \(e)")
			return
		}

		XCTAssert(decoded != nil)
		let value = decoded!["emoji"]
		XCTAssert(value != nil)
		let emojiStr = decoded!["emoji"] as! String
		XCTAssert(emojiStr == "😳")
	}



	func testNetSendFile() {

		let testFile = File("/tmp/file_to_send.txt")
		let testContents = "Here are the contents"
		let sock = "/tmp/foo.sock"
		let sockFile = File(sock)
		if sockFile.exists {
			sockFile.delete()
		}

		do {

			try testFile.open(.truncate)
			let _ = try testFile.write(string: testContents)
			testFile.close()
			try testFile.open()

			let server = NetNamedPipe()
			let client = NetNamedPipe()

			try server.bind(address: sock)
			server.listen()

			let serverExpectation = self.expectation(withDescription: "server")
			let clientExpectation = self.expectation(withDescription: "client")

			try server.accept(timeoutSeconds: NetEvent.noTimeout) {
				(inn: NetTCP?) -> () in
				let n = inn as? NetNamedPipe
				XCTAssertNotNil(n)

				do {
					try n?.sendFile(testFile) {
						(b: Bool) in

						XCTAssertTrue(b)

						n!.close()

						serverExpectation.fulfill()
					}
				} catch let e {
					XCTAssert(false, "Exception accepting connection: \(e)")
					serverExpectation.fulfill()
				}
			}

			try client.connect(address: sock, timeoutSeconds: 5) {
				(inn: NetTCP?) -> () in
				let n = inn as? NetNamedPipe
				XCTAssertNotNil(n)
				do {
					try n!.receiveFile {
						f in

						XCTAssertNotNil(f)
						do {
							let testDataRead = try f!.readSomeBytes(count: f!.size)
							if testDataRead.count > 0 {
								XCTAssertEqual(UTF8Encoding.encode(bytes: testDataRead), testContents)
							} else {
								XCTAssertTrue(false, "Got no data from received file")
							}
							f!.close()
						} catch let e {
							XCTAssert(false, "Exception in connection: \(e)")
						}
						clientExpectation.fulfill()
					}
				} catch let e {
					XCTAssert(false, "Exception in connection: \(e)")
					clientExpectation.fulfill()
				}
			}
			self.waitForExpectations(withTimeout: 10000, handler: {
				_ in
				server.close()
				client.close()
				testFile.close()
				testFile.delete()
			})
		} catch PerfectError.networkError(let code, let msg) {
			XCTAssert(false, "Exception: \(code) \(msg)")
		} catch let e {
			XCTAssert(false, "Exception: \(e)")
		}
	}

	func testSysProcess() {
#if !Xcode  // this always fails in Xcode but passes on the cli and on Linux.
            // I think it's some interaction with the debugger. System call interrupted.
		do {
			let proc = try SysProcess("ls", args:["-l", "/"], env:[("PATH", "/usr/bin:/bin")])

			XCTAssertTrue(proc.isOpen())
			XCTAssertNotNil(proc.stdin)

			let fileOut = proc.stdout!
			let data = try fileOut.readSomeBytes(count: 4096)

			XCTAssertTrue(data.count > 0)

			let waitRes = try proc.wait()

			XCTAssert(0 == waitRes, "\(waitRes) \(UTF8Encoding.encode(bytes: data))")

			proc.close()
		} catch {
			XCTAssert(false, "Exception running SysProcess test: \(error)")
		}
#endif
	}

	func testStringByEncodingHTML() {
		let src = "<b>\"quoted\" '& ☃"
		let res = src.stringByEncodingHTML
		XCTAssertEqual(res, "&lt;b&gt;&quot;quoted&quot; &#39;&amp; &#9731;")
	}

	func testStringByEncodingURL() {
		let src = "This has \"weird\" characters & ßtuff"
		let res = src.stringByEncodingURL
		XCTAssertEqual(res, "This%20has%20%22weird%22%20characters%20&%20%C3%9Ftuff")
	}

	func testStringByDecodingURL() {
		let src = "This has \"weird\" characters & ßtuff"
		let mid = src.stringByEncodingURL
		guard let res = mid.stringByDecodingURL else {
			XCTAssert(false, "Got nil String")
			return
		}
		XCTAssert(res == src, "Bad URL decoding")
	}

	func testStringByDecodingURL2() {
		let src = "This is badly%PWencoded"
		let res = src.stringByDecodingURL

		XCTAssert(res == nil, "Bad URL decoding")
	}

	func testStringByReplacingString() {

		let src = "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ"
		let test = "ABCFEDGHIJKLMNOPQRSTUVWXYZABCFEDGHIJKLMNOPQRSTUVWXYZABCFEDGHIJKLMNOPQRSTUVWXYZ"
		let find = "DEF"
		let rep = "FED"

		let res = src.stringByReplacing(string: find, withString: rep)

		XCTAssert(res == test)
	}

	func testStringByReplacingString2() {

		let src = ""
		let find = "DEF"
		let rep = "FED"

		let res = src.stringByReplacing(string: find, withString: rep)

		XCTAssert(res == src)
	}

	func testStringByReplacingString3() {

		let src = "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ"
		let find = ""
		let rep = "FED"

		let res = src.stringByReplacing(string: find, withString: rep)

		XCTAssert(res == src)
	}

	func testSubstringTo() {

		let src = "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ"
		let res = src.substring(to: src.index(src.startIndex, offsetBy: 5))

		XCTAssert(res == "ABCDE")
	}

	func testRangeTo() {

		let src = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

		let res = src.range(ofString: "DEF")
		XCTAssert(res == src.index(src.startIndex, offsetBy: 3)..<src.index(src.startIndex, offsetBy: 6))

		let res2 = src.range(ofString: "FED")
		XCTAssert(res2 == nil)


		let res3 = src.range(ofString: "def", ignoreCase: true)
		XCTAssert(res3 == src.index(src.startIndex, offsetBy: 3)..<src.index(src.startIndex, offsetBy: 6))
	}

	func testSubstringWith() {

		let src = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		let range = src.index(src.startIndex, offsetBy: 3)..<src.index(src.startIndex, offsetBy: 6)
		XCTAssert("DEF" == src.substring(with: range))
	}

	func testStringBeginsWith() {
		let a = "123456"

		XCTAssert(a.begins(with: "123"))
		XCTAssert(!a.begins(with: "abc"))
	}

	func testStringEndsWith() {
		let a = "123456"

		XCTAssert(a.ends(with: "456"))
		XCTAssert(!a.ends(with: "abc"))
	}

    func testDeletingPathExtension() {
        let path = "/a/b/c.txt"
        let del = path.stringByDeletingPathExtension
        XCTAssert("/a/b/c" == del)
    }

    func testGetPathExtension() {
        let path = "/a/b/c.txt"
        let ext = path.pathExtension
        XCTAssert("txt" == ext)
    }

    func testDirCreate() {
        let path = "/tmp/a/b/c/d/e/f/g"
        do {
            try Dir(path).create()

            XCTAssert(Dir(path).exists)

            var unPath = path

            while unPath != "/tmp" {
                try Dir(unPath).delete()
                unPath = unPath.stringByDeletingLastPathComponent
            }
        } catch {
            XCTAssert(false, "Error while creating dirs: \(error)")
        }
    }

    func testDirCreateRel() {
        let path = "a/b/c/d/e/f/g"
        do {
            try Dir(path).create()
            XCTAssert(Dir(path).exists)
            var unPath = path
            repeat {
                try Dir(unPath).delete()

								// this was killing linux on the final path component
								//unPath = unPath.stringByDeletingLastPathComponent

								var splt = unPath.characters.split(separator: "/").map(String.init)
								splt.removeLast()
								unPath = splt.joined(separator: "/")

            } while !unPath.isEmpty
        } catch {
					print(error)
            XCTAssert(false, "Error while creating dirs: \(error)")
        }
    }

    func testDirForEach() {
        let dirs = ["a/", "b/", "c/"]
        do {
            try Dir("/tmp/a").create()
            for d in dirs {
                try Dir("/tmp/a/\(d)").create()
            }
            var ta = [String]()
            try Dir("/tmp/a").forEachEntry {
                name in
                ta.append(name)
            }
						ta.sort()
            XCTAssert(ta == dirs, "\(ta) == \(dirs)")
            for d in dirs {
                try Dir("/tmp/a/\(d)").delete()
            }
            try Dir("/tmp/a").delete()
        } catch {
            XCTAssert(false, "Error while creating dirs: \(error)")
        }
    }
}

extension PerfectLibTests {
    static var allTests : [(String, (PerfectLibTests) -> () throws -> Void)] {
        return [
            ("testConcurrentQueue", testConcurrentQueue),
            ("testSerialQueue", testSerialQueue),
            ("testJSONConvertibleObject", testJSONConvertibleObject),
            ("testJSONEncodeDecode", testJSONEncodeDecode),
            ("testJSONDecodeUnicode", testJSONDecodeUnicode),
            ("testNetSendFile", testNetSendFile),
            ("testSysProcess", testSysProcess),
            ("testStringByEncodingHTML", testStringByEncodingHTML),
            ("testStringByEncodingURL", testStringByEncodingURL),
            ("testStringByDecodingURL", testStringByDecodingURL),
            ("testStringByDecodingURL2", testStringByDecodingURL2),
            ("testStringByReplacingString", testStringByReplacingString),
            ("testStringByReplacingString2", testStringByReplacingString2),
            ("testStringByReplacingString3", testStringByReplacingString3),
            ("testSubstringTo", testSubstringTo),
            ("testRangeTo", testRangeTo),
            ("testSubstringWith", testSubstringWith),

            ("testDeletingPathExtension", testDeletingPathExtension),
            ("testGetPathExtension", testGetPathExtension),

            ("testDirCreate", testDirCreate),
            ("testDirCreateRel", testDirCreateRel),
            ("testDirForEach", testDirForEach)
        ]
    }
}
