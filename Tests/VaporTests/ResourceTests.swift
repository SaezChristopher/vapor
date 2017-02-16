import XCTest
@testable import Vapor
import HTTP

class ResourceTests: XCTestCase {
    static let allTests = [
        ("testBasic", testBasic),
        ("testOptions", testOptions)
    ]

    func testBasic() throws {
        let drop = Droplet()

        drop.middleware = []

        let user = try User(from: "Hi")
        let node = try user?.makeNode()
        XCTAssertEqual(node, .object(["name":"Hi"]))

        drop.resource("users", User.self) { users in
            users.index = { req in
                return "index"
            }

            users.show = { req, user in
                return "user \(user.name)"
            }
        }

        XCTAssertEqual(try drop.responseBody(for: .get, "users"), "index")
        XCTAssertEqual(try drop.responseBody(for: .get, "users/bob"), "user bob")
        print(try drop.responseBody(for: .get, "users/ERROR"))
        XCTAssert(try drop.responseBody(for: .get, "users/ERROR").contains("Abort.notFound"))
    }

    func testOptions() throws {
        let drop = Droplet()

        drop.resource("users", User.self) { users in
            users.index = { req in
                return "index"
            }
            users.store = { req in
                return "store"
            }
        }

        XCTAssert(try drop.responseBody(for: .options, "users").contains("methods"))
        XCTAssert(try drop.responseBody(for: .options, "users/5").contains("methods"))
    }

}
