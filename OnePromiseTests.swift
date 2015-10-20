import UIKit
import XCTest

class OnePromiseTests: XCTestCase {

    func testCreateWithBlock() {
        let expectation = self.expectationWithDescription("done")

        let promise: Promise<Int> = Promise { (promise) in
            dispatch_async(dispatch_get_main_queue()) {
                promise.fulfill(1)
            }
        }

        promise.then({ (value) -> Void in
            XCTAssertEqual(value, 1)
            expectation.fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testPromiseCallbackReturnsSameTypeAsValueType() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise
            .then({ (value:Int) -> Int in
                return value * 2
            })
            .then({ (value:Int) in
                XCTAssertEqual(value, 2000)
                expectation.fulfill()
            })

        promise.fulfill(1000)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

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
            .then(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { (s) in
                XCTAssertEqual(s, "2000")
                expectation.fulfill()
            })

        promise.fulfill(1000)

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: child promise
extension OnePromiseTests {
    func testChildPromiseOfPendingPromise() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise
            .then({ (i) in
                Promise<Double> { (p) in
                    dispatch_async(dispatch_get_main_queue()) {
                        p.fulfill(Double(i))
                    }
                }
            })
            .then({ (d) -> Void in
                XCTAssertEqualWithAccuracy(d, 2.0, accuracy: 0.01)
                expectation.fulfill()
            })

        dispatch_async(dispatch_get_main_queue()) {
            promise.fulfill(2)
        }

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testChildPromiseOfPendingPromiseToBeRejected() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise
            .then({ (i) in
                Promise<Double> { (p) in
                    dispatch_async(dispatch_get_main_queue()) {
                        p.fulfill(Double(i))
                    }
                }
            })
            .then({ (d) -> Void in
                XCTFail()
            }, { (e: NSError) in
                expectation.fulfill()
            })

        dispatch_async(dispatch_get_main_queue()) {
            promise.reject(NSError(domain: "", code: -1, userInfo: nil))
        }

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testChildPromiseOfFulfilledPromise() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise.fulfill(2)

        promise
            .then({ (i) in
                Promise<Double> { (p) in
                    p.fulfill(Double(i))
                }
            })
            .then({ (d) -> Void in
                XCTAssertEqualWithAccuracy(d, 2.0, accuracy: 0.01)
                expectation.fulfill()
            })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: onFulfilled
extension OnePromiseTests {
    func testOnFulfilledSequence() {
        // Executation queue: we need serial queue for thread sefety
        let serialQueue = dispatch_get_main_queue()

        // Expectations: verify callbacks order
        var i = 0
        var expectations = [XCTestExpectation]()

        expectations.append(self.expectationWithDescription("1"))
        expectations.append(self.expectationWithDescription("2"))
        expectations.append(self.expectationWithDescription("3"))
        expectations.append(self.expectationWithDescription("4"))

        // Promise and callback registration
        let promise = Promise<Int>()

        promise
            .then(serialQueue, { (value) -> Void in
                XCTAssertEqual(i, 0)
                expectations[i++].fulfill()
            })
            .then(serialQueue, { (value) -> Void in
                XCTAssertEqual(i, 3)
                expectations[i++].fulfill()
            })

        promise.then(serialQueue, { (value) -> Void in
            XCTAssertEqual(i, 1)
            expectations[i++].fulfill()
        })

        promise.fulfill(1000)

        promise.then(serialQueue, { (value) -> Void in
            XCTAssertEqual(i, 2)
            expectations[i++].fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testOnFulfilledNeverCalledIfAlreadyRejected() {
        let expectation = self.expectationWithDescription("wait")

        let promise = Promise<Int>()

        promise.reject(NSError(domain: "", code: -1, userInfo: nil))

        promise
            .then({ (value) -> Promise<Int> in
                XCTFail()
                return Promise<Int>()
            })
            .then({ (value) in
                XCTFail()
            })

        dispatch_async(dispatch_get_main_queue()) {
            expectation.fulfill()
        }

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testPropagateFulfillToChildPromises() {
        let expectation = self.expectationWithDescription("wait")

        let promise = Promise<Int>()

        promise
            .then(nil, { (e: NSError) in
                XCTFail()
            })
            .then({ (value) in
                XCTAssertEqual(value, 123)
                expectation.fulfill()
            })

        promise.fulfill(123)

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: onRejected
extension OnePromiseTests {
    func testOnRejectedSequence() {
        // Executation queue: we need serial queue for thread sefety
        let serialQueue = dispatch_get_main_queue()

        // Expectations: verify callbacks order
        var i = 0
        var expectations = [XCTestExpectation]()

        expectations.append(self.expectationWithDescription("1"))
        expectations.append(self.expectationWithDescription("2"))
        expectations.append(self.expectationWithDescription("3"))
        expectations.append(self.expectationWithDescription("4"))

        // Promise and callback registration
        let promise = Promise<Int>()

        promise
            .then(serialQueue, nil, { (e: NSError) -> Void in
                XCTAssertEqual(i, 0)
                expectations[i++].fulfill()
            })
            .then(serialQueue, nil, { (e: NSError) -> Void in
                XCTAssertEqual(i, 3)
                expectations[i++].fulfill()
            })

        promise.then(serialQueue, nil, { (e: NSError) -> Void in
            XCTAssertEqual(i, 1)
            expectations[i++].fulfill()
        })

        promise.reject(NSError(domain: "", code: -1, userInfo: nil))

        promise.then(serialQueue, nil, { (e: NSError) -> Void in
            XCTAssertEqual(i, 2)
            expectations[i++].fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testOnRejectedNeverCalledIfAlreadyFulfilled() {
        let expectation = self.expectationWithDescription("wait")

        let promise = Promise<Int>()

        promise.fulfill(1)

        promise
            .then(nil, { (e: NSError) -> Void in
                XCTFail()
            })

        dispatch_async(dispatch_get_main_queue()) {
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testPropagateRejectionToChildPromises() {
        let expectation = self.expectationWithDescription("wait")

        let promise = Promise<Int>()
        let error   = NSError(domain: "dummy", code: 123, userInfo: nil)

        promise
            .then({ (value) in

            })
            .then(nil, { (e: NSError) in
                XCTAssertEqual(e, error)
                expectation.fulfill()
            })

        promise.reject(error)

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: onRejected: Error propagation
extension OnePromiseTests {
    enum SomeError: ErrorType {
        case IntError(Int)
    }

    func testPropagateSwiftErrorType() {
        let expectation = self.expectationWithDescription("wait")
        let promise = Promise<Int>()

        promise
            .then({ (i) throws -> Void in
                throw SomeError.IntError(i)
            })
            .then(nil, { (e: NSError) in
                XCTAssertEqual(e.domain, "OnePromise_Tests.OnePromiseTests.SomeError")
                expectation.fulfill()
            })

        promise.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testPropagateNSError() {
        let expectation = self.expectationWithDescription("wait")
        let promise = Promise<Int>()

        promise
            .then({ (i) throws -> Void in
                throw NSError(domain: "test.SomeError", code: 123, userInfo: nil)
            })
            .then(nil, { (e: NSError) in
                XCTAssertEqual(e.domain, "test.SomeError")
                XCTAssertEqual(e.code, 123)
                expectation.fulfill()
            })

        promise.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testPropagateNSErrorInCallbackReturnsPromise() {
        let expectation = self.expectationWithDescription("wait")
        let promise = Promise<Int>()

        promise
            .then({ (i) throws -> Promise<Int> in
                throw NSError(domain: "test.SomeError", code: 123, userInfo: nil)
            })
            .then(nil, { (e: NSError) in
                XCTAssertEqual(e.domain, "test.SomeError")
                XCTAssertEqual(e.code, 123)
                expectation.fulfill()
            })

        promise.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    /// An error occurred in a child promise should be propagated to
    /// following promises.
    func testErrorPropagationFromChildPromise() {
        let expectation = self.expectationWithDescription("wait")

        let error   = self.generateRandomError()
        let promise = Promise<Int>()

        promise
            .then({ (i) throws -> Promise<Int> in
                return Promise<Int> { (promise) in
                    promise.reject(error)
                }
            })
            .then(nil, { (e: NSError) in
                XCTAssertEqual(e, error)
                expectation.fulfill()
            })

        promise.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: State
extension OnePromiseTests {
    func testFulfilledStateMustNotTransitionToAnyOtherState() {
        let expectation = self.expectationWithDescription("wait")

        let promise = Promise<Int>()

        promise.fulfill(10)
        promise.fulfill(20)

        promise.then({ (value) in
            XCTAssertEqual(value, 10)
            expectation.fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: CustomStringConvertible
extension OnePromiseTests {
    func testDescription() {
        let promise = Promise<Int>()

        XCTAssertEqual("\(promise)", "Promise (Pending)")

        promise.fulfill(10)
        XCTAssertEqual("\(promise)", "Promise (Fulfilled)")

        let promise2 = Promise<Int>()

        promise2.reject(NSError(domain: "", code: -1, userInfo: nil))
        XCTAssertEqual("\(promise2)", "Promise (Rejected)")
    }
}

// MARK: Helpers
extension OnePromiseTests {
    private func generateRandomError() -> NSError {
        let code = Int(arc4random_uniform(101) + 100)

        return NSError(domain: "test.SomeError", code: code, userInfo: nil)
    }
}
