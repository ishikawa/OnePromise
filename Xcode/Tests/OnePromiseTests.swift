import UIKit
import XCTest
import OnePromise

class OnePromiseTests: XCTestCase {

    func createPromise() -> Promise<Int> {
        return Promise()
    }

    func testExample() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise
            .then({ (v) -> Int in
                v * 2
            })
            .then({ (v:Int) -> Promise<Double> in
                XCTAssertEqual(v, 2000)
                expectation.fulfill()

                return Promise()
            })
            .then({ (v) in

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
