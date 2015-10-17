import UIKit
import XCTest
import OnePromise

class OnePromiseTests: XCTestCase {

    func testExample() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise
            .then({
                $0 * 2
            })
            .then({ (i) -> Promise<String> in

                XCTAssertEqual(i, 2000)

                let np = Promise<String>()

                np.fulfill("\(i)")

                return np
            })
            .then(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), { (s) in
                expectation.fulfill()
                XCTAssertEqual(s, "2000")
            })

        promise.fulfill(1000)

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testOnRejected() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise.then(nil, { (e:NSError) -> Void in
            expectation.fulfill()
        })

        promise.reject(NSError(domain: "", code: -1, userInfo: nil))

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}
