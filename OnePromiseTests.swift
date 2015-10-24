import UIKit
import XCTest

private var testQueueTag = 0xbeaf

private let kOnePromiseTestsQueue: dispatch_queue_t = {
    let q = dispatch_queue_create("jp.ko9.OnePromiseTest", DISPATCH_QUEUE_CONCURRENT)

    dispatch_queue_set_specific(q, &testQueueTag, &testQueueTag, nil)

    return q
    }()

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
}

// MARK: Dispatch Queue
extension OnePromiseTests {
    func testDispatchQueue() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise
            .then({ (i) -> Int in
                XCTAssertFalse(self.isInTestDispatchQueue())
                return i * 2
            })
            .then(kOnePromiseTestsQueue, { (i) -> Promise<String> in
                XCTAssertTrue(self.isInTestDispatchQueue())
                XCTAssertEqual(i, 2000)

                let np = Promise<String>()

                np.fulfill("\(i)")

                return np
            })
            .then(kOnePromiseTestsQueue, { (s) in
                XCTAssertTrue(self.isInTestDispatchQueue())
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
            promise.reject(self.generateRandomError())
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

        promise.reject(self.generateRandomError())

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
        let error   = self.generateRandomError()
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

        promise.reject(error)

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
        let error   = self.generateRandomError()

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
                XCTAssertTrue(e.domain.hasSuffix(".OnePromiseTests.SomeError"))
                expectation.fulfill()
            })

        promise.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testPropagateNSError() {
        let expectation = self.expectationWithDescription("wait")

        let error   = self.generateRandomError()
        let promise = Promise<Int>()

        promise
            .then({ (i) throws -> Void in
                throw error
            })
            .then(nil, { (e: NSError) in
                XCTAssertEqual(e, error)
                expectation.fulfill()
            })

        promise.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testPropagateNSErrorInCallbackReturnsPromise() {
        let expectation = self.expectationWithDescription("wait")

        let error   = self.generateRandomError()
        let promise = Promise<Int>()

        promise
            .then({ (i) throws -> Promise<Int> in
                throw error
            })
            .then(nil, { (e: NSError) in
                XCTAssertEqual(e, error)
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

// MARK: resolve and reject
extension OnePromiseTests {
    func testResolve() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>.resolve(100)

        promise.then({
            XCTAssertEqual($0, 100)
            expectation.fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testResolveWithPromise() {
        let promise1 = Promise<Int>()
        let promise2 = Promise<Int>.resolve(promise1)

        XCTAssertTrue(promise1 === promise2)
    }

    func testRejectedPromise() {
        let expectation = self.expectationWithDescription("done")

        let error   = self.generateRandomError()
        let promise = Promise<Int>.reject(error)

        promise.caught({
            XCTAssertEqual($0, error)
            expectation.fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: caught
extension OnePromiseTests {
    func testFail() {
        let expectation = self.expectationWithDescription("done")

        let error   = self.generateRandomError()
        let promise = Promise<Int>()

        promise.caught({
            XCTAssertEqual($0, error)
            expectation.fulfill()
        })

        promise.reject(error)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testFailWithDispatchQueue() {
        let expectation = self.expectationWithDescription("done")

        let error   = self.generateRandomError()
        let promise = Promise<Int>()

        promise.caught(kOnePromiseTestsQueue, {
            XCTAssertTrue(self.isInTestDispatchQueue())
            XCTAssertEqual($0, error)
            expectation.fulfill()
        })

        promise.reject(error)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: finally
extension OnePromiseTests {
    func testFin() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise.finally({
            expectation.fulfill()
        })

        promise.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testFinWithDispatchQueue() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise.finally(kOnePromiseTestsQueue, {
            XCTAssertTrue(self.isInTestDispatchQueue())
            expectation.fulfill()
        })

        promise.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testFinWithRejection() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise.finally({
            expectation.fulfill()
        })

        promise.reject(self.generateRandomError())
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testThenFin() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>()

        promise
            .then({ (_) -> Void in

            })
            .finally({
                expectation.fulfill()
            })

        promise.reject(self.generateRandomError())
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: Collection
extension OnePromiseTests {

    func testAllPromisesFulfilled() {
        var promises: [Promise<Int>] = []

        for i in 1...10 {
            let subexpectation = self.expectationWithDescription("Promise \(i)")
            let subpromise = Promise<Int>()

            subpromise
                .then({ (_) -> Void in
                    subexpectation.fulfill()
                })

            promises.append(subpromise)
        }

        let expectation = self.expectationWithDescription("All done")

        Promise.all(promises)
            .then(kOnePromiseTestsQueue, { (_) -> Void in
                XCTAssertTrue(self.isInTestDispatchQueue())
                expectation.fulfill()
            })
            .caught({ (_) -> Void in
                XCTFail()
            })

        for promise in promises {
            promise.fulfill(1)
        }

        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }

    func testAnyPromisesRejected() {
        var promises: [Promise<Int>] = []

        for _ in 1...10 {
            promises.append(Promise<Int>())
        }

        let expectation = self.expectationWithDescription("All done")

        Promise.all(promises)
            .then({ (_) -> Void in
                XCTFail()
            })
            .caught(kOnePromiseTestsQueue, { (_) -> Void in
                XCTAssertTrue(self.isInTestDispatchQueue())
                expectation.fulfill()
            })

        let error = self.generateRandomError()
        let rejectTarget = promises.popLast()!

        for promise in promises {
            promise.fulfill(2)
        }

        rejectTarget.reject(error)

        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
}

// MARK: Helpers
extension OnePromiseTests {
    private func generateRandomError() -> NSError {
        let code = Int(arc4random_uniform(10001))

        return NSError(domain: "test.SomeError", code: code, userInfo: nil)
    }

    private func isInTestDispatchQueue() -> Bool {
        return dispatch_get_specific(&testQueueTag) != nil
    }
}

