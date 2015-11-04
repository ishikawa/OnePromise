import UIKit
import XCTest
import OnePromise

private var testQueueTag = 0xbeaf

private let kOnePromiseTestsQueue: dispatch_queue_t = {
    let q = dispatch_queue_create("jp.ko9.OnePromiseTest", DISPATCH_QUEUE_CONCURRENT)

    dispatch_queue_set_specific(q, &testQueueTag, &testQueueTag, nil)

    return q
}()

enum ErrorWithValue: ErrorType {
    case IntError(Int)
    case StrError(String)
}

class OnePromiseTests: XCTestCase {

    func testCreateWithBlock() {
        let expectation = self.expectationWithDescription("done")

        let promise: Promise<Int> = Promise { (fulfill, _) in
            dispatch_async(dispatch_get_main_queue()) {
                fulfill(1)
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

        let deferred = Promise<Int>.deferred()

        deferred.promise
            .then({ (value:Int) -> Int in
                return value * 2
            })
            .then({ (value:Int) in
                XCTAssertEqual(value, 2000)
                expectation.fulfill()
            })

        deferred.fulfill(1000)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testCreateWithBlockThrows() {
        let expectation = self.expectationWithDescription("done")

        let promise: Promise<Void> = Promise<Void>({ (_, _) throws in
            throw ErrorWithValue.IntError(1000)
        })

        promise.caught({ (error) -> Void in
            XCTAssert(error.domain.hasSuffix(".ErrorWithValue"))
            expectation.fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: Swift type inference
extension OnePromiseTests {
    func testTypeInference1() {
        let expectation = self.expectationWithDescription("done")

        let deferred1 = Promise<Int>.deferred()
        let deferred2 = Promise<Int>.deferred()

        let promise1 = deferred1.promise
        let promise2 = deferred2.promise

        var i = 0

        promise1.then({ (_) in XCTAssertEqual(i++, 0) })
        promise2.then({ (_) in XCTAssertEqual(i++, 1) })

        // Because `then A` returns the Promise, the handler in `then B` must be
        // invoked after `then A` promise fulfilled.
        let _: Promise<Void> = promise1
            // then A
            .then({
                (_) in  // should be: (_) -> Promise<Int> in

                return promise2
            })
            // then B
            .then({ (_) -> Void in
                XCTAssertEqual(i++, 2)
                expectation.fulfill()
            })

        deferred1.fulfill(1)
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            deferred2.fulfill(2)
        }

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: Deferred
extension OnePromiseTests {
    func testDeferredFulfill() {
        let expectation = self.expectationWithDescription("done")

        let deferred = Promise<Int>.deferred()

        deferred.promise
            .then({
                XCTAssertEqual($0, 199)
                expectation.fulfill()
            })

        dispatch_async(dispatch_get_main_queue()) {
            deferred.fulfill(199)
        }

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testDeferredReject() {
        let expectation = self.expectationWithDescription("done")

        let (promise, _, reject) = Promise<Int>.deferred()

        promise
            .caught({ (_) in
                expectation.fulfill()
            })

        dispatch_async(dispatch_get_main_queue()) {
            reject(self.generateRandomError())
        }

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: Dispatch Queue
extension OnePromiseTests {
    func testDispatchQueue() {
        let expectation = self.expectationWithDescription("done")

        let deferred = Promise<Int>.deferred()

        deferred.promise
            .then({ (i) -> Int in
                XCTAssertFalse(self.isInTestDispatchQueue())
                return i * 2
            })
            .then(kOnePromiseTestsQueue, { (i) -> Promise<String> in
                XCTAssertTrue(self.isInTestDispatchQueue())
                XCTAssertEqual(i, 2000)

                return Promise<String> { (fulfill, _) in
                    fulfill("\(i)")
                }
            })
            .then(kOnePromiseTestsQueue, { (s) in
                XCTAssertTrue(self.isInTestDispatchQueue())
                XCTAssertEqual(s, "2000")

                expectation.fulfill()
            })

        deferred.fulfill(1000)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: child promise
extension OnePromiseTests {
    func testChildPromiseOfPendingPromise() {
        let expectation = self.expectationWithDescription("done")

        let deferred = Promise<Int>.deferred()

        deferred.promise
            .then({ (i) in
                Promise<Double> { (fulfill, _) in
                    dispatch_async(dispatch_get_main_queue()) {
                        fulfill(Double(i))
                    }
                }
            })
            .then({ (d) -> Void in
                XCTAssertEqualWithAccuracy(d, 2.0, accuracy: 0.01)
                expectation.fulfill()
            })

        dispatch_async(dispatch_get_main_queue()) {
            deferred.fulfill(2)
        }

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testChildPromiseOfPendingPromiseToBeRejected() {
        let expectation = self.expectationWithDescription("done")

        let deferred = Promise<Int>.deferred()

        deferred.promise
            .then({ (i) in
                Promise<Double> { (fulfill, _) in
                    dispatch_async(dispatch_get_main_queue()) {
                        fulfill(Double(i))
                    }
                }
            })
            .then({ (d) -> Void in
                XCTFail()
                }, { (e: NSError) in
                    expectation.fulfill()
            })

        dispatch_async(dispatch_get_main_queue()) {
            deferred.reject(self.generateRandomError())
        }

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testChildPromiseOfFulfilledPromise() {
        let expectation = self.expectationWithDescription("done")

        let deferred = Promise<Int>.deferred()

        deferred.fulfill(2)

        deferred.promise
            .then({ (i) in
                Promise<Double> { (fulfill, _) in
                    fulfill(Double(i))
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
        let deferred = Promise<Int>.deferred()
        let promise  = deferred.promise

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

        deferred.fulfill(1000)

        promise.then(serialQueue, { (value) -> Void in
            XCTAssertEqual(i, 2)
            expectations[i++].fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testOnFulfilledNeverCalledIfAlreadyRejected() {
        let expectation = self.expectationWithDescription("wait")

        let deferred = Promise<Int>.deferred()
        let promise  = deferred.promise

        deferred.reject(self.generateRandomError())

        promise
            .then({ (value) -> Promise<Int> in
                XCTFail()
                return Promise<Int>() { (_, _) in }
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

        let deferred = Promise<Int>.deferred()

        deferred.promise
            .caught({ (e: NSError) in
                XCTFail()
            })
            .then({ (value) in
                XCTAssertEqual(value, 123)
                expectation.fulfill()
            })

        deferred.fulfill(123)

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
        let error = self.generateRandomError()
        let deferred = Promise<Int>.deferred()
        let promise  = deferred.promise

        promise
            .caught(serialQueue, { (e: NSError) -> Void in
                XCTAssertEqual(i, 0)
                expectations[i++].fulfill()
            })
            .caught(serialQueue, { (e: NSError) -> Void in
                XCTAssertEqual(i, 3)
                expectations[i++].fulfill()
            })

        promise.caught(serialQueue, { (e: NSError) -> Void in
            XCTAssertEqual(i, 1)
            expectations[i++].fulfill()
        })

        deferred.reject(error)

        promise.caught(serialQueue, { (e: NSError) -> Void in
            XCTAssertEqual(i, 2)
            expectations[i++].fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testOnRejectedNeverCalledIfAlreadyFulfilled() {
        let expectation = self.expectationWithDescription("wait")

        let deferred = Promise<Int>.deferred()

        deferred.fulfill(1)

        deferred.promise
            .caught({ (e: NSError) -> Void in
                XCTFail()
            })

        dispatch_async(dispatch_get_main_queue()) {
            expectation.fulfill()
        }

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testPropagateRejectionToChildPromises() {
        let expectation = self.expectationWithDescription("wait")

        let deferred = Promise<Int>.deferred()
        let error   = self.generateRandomError()

        deferred.promise
            .then({ (value) in

            })
            .caught({ (e: NSError) in
                XCTAssertEqual(e, error)
                expectation.fulfill()
            })

        deferred.reject(error)

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testOnRejectWithCustomErrorType() {
        let expectation = self.expectationWithDescription("done")
        let deferred = Promise<Int>.deferred()

        deferred.promise
            .caught({ (e: ErrorWithValue) in
                if case .IntError(let value) = e {
                    XCTAssertEqual(value, 2000)
                }
                expectation.fulfill()
            })

        deferred.reject(ErrorWithValue.IntError(2000) as NSError)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testOnRejectWithCustomErrorTypeThenFulfill() {
        let expectation = self.expectationWithDescription("done")
        let deferred = Promise<Int>.deferred()

        deferred.promise
            .caught({ (e: ErrorWithValue) in
                XCTFail()
            })
            .then({ (value) -> Void in
                XCTAssertEqual(value, 2000)
                expectation.fulfill()
            })

        deferred.fulfill(2000)
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
        let deferred = Promise<Int>.deferred()

        deferred.promise
            .then({ (i) throws -> Void in
                throw SomeError.IntError(i)
            })
            .caught({ (e: NSError) in
                XCTAssertTrue(e.domain.hasSuffix(".OnePromiseTests.SomeError"))
                expectation.fulfill()
            })

        deferred.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testPropagateNSError() {
        let expectation = self.expectationWithDescription("wait")

        let error   = self.generateRandomError()
        let deferred = Promise<Int>.deferred()

        deferred.promise
            .then({ (i) throws -> Void in
                throw error
            })
            .caught({ (e: NSError) in
                XCTAssertEqual(e, error)
                expectation.fulfill()
            })

        deferred.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testPropagateNSErrorInCallbackReturnsPromise() {
        let expectation = self.expectationWithDescription("wait")

        let error   = self.generateRandomError()
        let deferred = Promise<Int>.deferred()

        deferred.promise
            .then({ (i) throws -> Promise<Int> in
                throw error
            })
            .caught({ (e: NSError) in
                XCTAssertEqual(e, error)
                expectation.fulfill()
            })

        deferred.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    /// An error occurred in a child promise should be propagated to
    /// following promises.
    func testErrorPropagationFromChildPromise() {
        let expectation = self.expectationWithDescription("wait")

        let error   = self.generateRandomError()
        let deferred = Promise<Int>.deferred()

        deferred.promise
            .then({ (i) throws -> Promise<Int> in
                return Promise<Int> { (_, reject) in
                    reject(error)
                }
            })
            .caught({ (e: NSError) in
                XCTAssertEqual(e, error)
                expectation.fulfill()
            })

        deferred.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: State
extension OnePromiseTests {
    func testFulfilledStateMustNotTransitionToAnyOtherState() {
        let expectation = self.expectationWithDescription("wait")

        let deferred = Promise<Int>.deferred()

        deferred.fulfill(10)
        deferred.fulfill(20)

        deferred.promise.then({ (value) in
            XCTAssertEqual(value, 10)
            expectation.fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: CustomStringConvertible
extension OnePromiseTests {
    func testDescription() {
        let deferred = Promise<Int>.deferred()

        XCTAssertEqual("\(deferred.promise)", "Promise (Pending)")

        deferred.fulfill(10)
        XCTAssertEqual("\(deferred.promise)", "Promise (Fulfilled)")

        let deferred2 = Promise<Int>.deferred()

        deferred2.reject(NSError(domain: "", code: -1, userInfo: nil))
        XCTAssertEqual("\(deferred2.promise)", "Promise (Rejected)")
    }
}

// MARK: resolve and reject
extension OnePromiseTests {
    func testResolve() {
        let expectation1 = self.expectationWithDescription("done")
        let expectation2 = self.expectationWithDescription("done")

        let promise1 = Promise<Int>.resolve(100)
        let promise2 = Promise.resolve("string value")

        promise1.then({
            XCTAssertEqual($0, 100)
            expectation1.fulfill()
        })
        promise2.then({
            XCTAssertEqual($0, "string value")
            expectation2.fulfill()
        })

        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testResolveWithPromise() {
        let promise1 = Promise<Int>.resolve(100)
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

    func testRejectedWithErrorTypePromise() {
        let expectation = self.expectationWithDescription("done")

        let promise = Promise<Int>.reject(ErrorWithValue.StrError("panic!"))

        promise.caught({ (err: ErrorWithValue) in
            if case .StrError(let str) = err {
                XCTAssertEqual(str, "panic!")
            }
            else {
                XCTFail()
            }

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
        let deferred = Promise<Int>.deferred()

        deferred.promise.caught({
            XCTAssertEqual($0, error)
            expectation.fulfill()
        })

        deferred.reject(error)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testFailWithDispatchQueue() {
        let expectation = self.expectationWithDescription("done")

        let error   = self.generateRandomError()
        let deferred = Promise<Int>.deferred()

        deferred.promise
            .caught(kOnePromiseTestsQueue, {
                XCTAssertTrue(self.isInTestDispatchQueue())
                XCTAssertEqual($0, error)
                expectation.fulfill()
            })

        deferred.reject(error)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: finally
extension OnePromiseTests {
    func testFin() {
        let expectation = self.expectationWithDescription("done")

        let deferred = Promise<Int>.deferred()

        deferred.promise.finally({
            expectation.fulfill()
        })

        deferred.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testFinWithDispatchQueue() {
        let expectation = self.expectationWithDescription("done")

        let deferred = Promise<Int>.deferred()

        deferred.promise.finally(kOnePromiseTestsQueue, {
            XCTAssertTrue(self.isInTestDispatchQueue())
            expectation.fulfill()
        })

        deferred.fulfill(1)
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testFinWithRejection() {
        let expectation = self.expectationWithDescription("done")

        let deferred = Promise<Int>.deferred()

        deferred.promise.finally({
            expectation.fulfill()
        })

        deferred.reject(self.generateRandomError())
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }

    func testThenFin() {
        let expectation = self.expectationWithDescription("done")

        let deferred = Promise<Int>.deferred()

        deferred.promise
            .then({ (_) -> Void in

            })
            .finally({
                expectation.fulfill()
            })

        deferred.reject(self.generateRandomError())
        self.waitForExpectationsWithTimeout(1.0, handler: nil)
    }
}

// MARK: Promise.all
extension OnePromiseTests {
    func testAllPromisesFulfilled() {
        var promises: [Promise<Int>] = []
        var fulfillers: [Int -> Void] = []

        for i in 1...10 {
            let subexpectation = self.expectationWithDescription("Promise \(i)")
            let d = Promise<Int>.deferred()

            d.promise
                .then({ (_) -> Void in
                    subexpectation.fulfill()
                })

            promises.append(d.promise)
            fulfillers.append(d.fulfill)
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

        for f in fulfillers {
            f(1)
        }

        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }

    func testAnyPromisesRejected() {
        var promises: [Promise<Int>] = []
        var fulfillers: [Int -> Void] = []
        var rejecters: [NSError -> Void] = []

        for _ in 1...10 {
            let d = Promise<Int>.deferred()

            promises.append(d.promise)
            fulfillers.append(d.fulfill)
            rejecters.append(d.reject)
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

        fulfillers.popLast()

        for f in fulfillers {
            f(2)
        }

        rejecters.last!(error)

        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
}

// MARK: Promise.join
extension OnePromiseTests {
    // Promise.join/2
    func testJoinedTwoPromisesFulfilled() {
        let intDeferred = Promise<Int>.deferred()
        let strDeferred = Promise<String>.deferred()
        let intPromise  = intDeferred.promise
        let strPromise  = strDeferred.promise

        let expectation1 = self.expectationWithDescription("Int Promise")
        let expectation2 = self.expectationWithDescription("String Promise")

        intPromise
            .then({ (_) -> Void in
                expectation1.fulfill()
            })
        strPromise
            .then({ (_) -> Void in
                expectation2.fulfill()
            })

        let expectation = self.expectationWithDescription("All done")

        Promise.join(intPromise, strPromise)
            .then(kOnePromiseTestsQueue, { (value1, value2) -> Void in
                XCTAssertTrue(self.isInTestDispatchQueue())
                XCTAssertEqual(value1, 1000)
                XCTAssertEqual(value2, "string value")

                expectation.fulfill()
            })
            .caught({ (error: NSError) -> Void in
                XCTFail()
            })

        intDeferred.fulfill(1000)
        strDeferred.fulfill("string value")

        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }

    func testJoinedTwoPromisesRejected() {
        let intDeferred = Promise<Int>.deferred()
        let strDeferred = Promise<String>.deferred()

        let intPromise = intDeferred.promise
        let strPromise = strDeferred.promise

        let expectation1 = self.expectationWithDescription("Int Promise")
        let expectation2 = self.expectationWithDescription("String Promise")

        intPromise
            .then({ (_) -> Void in
                expectation1.fulfill()
            })
        strPromise
            .caught({ (e: NSError) -> Void in
                expectation2.fulfill()
            })

        let error = self.generateRandomError()
        let expectation = self.expectationWithDescription("All done")

        Promise.join(intPromise, strPromise)
            .then(kOnePromiseTestsQueue, { (value1, value2) -> Void in
                XCTFail()
            })
            .caught(kOnePromiseTestsQueue, { (e: NSError) -> Void in
                XCTAssertTrue(self.isInTestDispatchQueue())
                XCTAssertEqual(e, error)
                expectation.fulfill()
            })

        intDeferred.fulfill(1000)
        strDeferred.reject(error)

        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }

    // Promise.join/3
    func testJoinedThreePromisesFulfilled() {
        let intDeferred    = Promise<Int>.deferred()
        let strDeferred    = Promise<String>.deferred()
        let doubleDeferred = Promise<Double>.deferred()

        let intPromise    = intDeferred.promise
        let strPromise    = strDeferred.promise
        let doublePromise = doubleDeferred.promise

        let expectation1 = self.expectationWithDescription("Int Promise")
        let expectation2 = self.expectationWithDescription("String Promise")
        let expectation3 = self.expectationWithDescription("String Promise")

        intPromise
            .then({ (_) -> Void in
                expectation1.fulfill()
            })
        strPromise
            .then({ (_) -> Void in
                expectation2.fulfill()
            })
        doublePromise
            .then({ (_) -> Void in
                expectation3.fulfill()
            })

        let expectation = self.expectationWithDescription("All done")

        Promise.join(intPromise, strPromise, doublePromise)
            .then(kOnePromiseTestsQueue, { (value1, value2, value3) -> Void in
                XCTAssertTrue(self.isInTestDispatchQueue())
                XCTAssertEqual(value1, 1000)
                XCTAssertEqual(value2, "string value")
                XCTAssertEqualWithAccuracy(value3, 2000.0, accuracy: 0.01)

                expectation.fulfill()
            })
            .caught({ (error: NSError) -> Void in
                XCTFail()
            })

        intDeferred.fulfill(1000)
        strDeferred.fulfill("string value")
        doubleDeferred.fulfill(2000.0)

        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }

    func testJoinedThreePromisesRejected() {
        let error = self.generateRandomError()

        let intDeferred    = Promise<Int>.deferred()
        let strDeferred    = Promise<String>.deferred()
        let doubleDeferred = Promise<Double>.deferred()

        let intPromise    = intDeferred.promise
        let strPromise    = strDeferred.promise
        let doublePromise = doubleDeferred.promise

        let expectation1 = self.expectationWithDescription("Int Promise")
        let expectation2 = self.expectationWithDescription("String Promise")
        let expectation3 = self.expectationWithDescription("String Promise")

        intPromise
            .then({ (_) -> Void in
                expectation1.fulfill()
            })
        strPromise
            .caught({ (e) -> Void in
                XCTAssertEqual(e, error)
                expectation2.fulfill()
            })
        doublePromise
            .then({ (_) -> Void in
                expectation3.fulfill()
            })

        let expectation = self.expectationWithDescription("All done")

        Promise.join(intPromise, strPromise, doublePromise)
            .then(kOnePromiseTestsQueue, { (_, _, _) -> Void in
                XCTFail()
            })
            .caught(kOnePromiseTestsQueue, { (e: NSError) -> Void in
                XCTAssertTrue(self.isInTestDispatchQueue())
                XCTAssertEqual(e, error)
                expectation.fulfill()
            })

        intDeferred.fulfill(1000)
        doubleDeferred.fulfill(2000.0)
        strDeferred.reject(error)

        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
}

// MARK: Timer
extension OnePromiseTests {
    func testDelay() {
        self.delayTest {
            Promise
                .resolve(1000)
                .delay($0)
                .then({ (value) in
                    XCTAssertEqual(value, 1000)
                })
        }
    }

    func testDelayValue() {
        self.delayTest {
            Promise
                .delay(2000, $0)
                .then({ (value) in
                    XCTAssertEqual(value, 2000)
                })
        }
    }

    func testDelayPromise() {
        self.delayTest {
            Promise
                .delay(Promise.resolve(3000), $0)
                .then({ (value) in
                    XCTAssertEqual(value, 3000)
                })
        }
    }

    private func delayTest<T>(timeToPromisifier: (NSTimeInterval) -> Promise<T>) {
        let expectation = self.expectationWithDescription("done")

        var resolved = false

        // (1) pre condition
        do {
            let time = dispatch_time(DISPATCH_TIME_NOW, Int64(0.1 * Double(NSEC_PER_SEC)))

            dispatch_after(time, kOnePromiseTestsQueue, {
                XCTAssertFalse(resolved)
                XCTAssertTrue(self.isInTestDispatchQueue())
            })
        }

        // (2) resolution later
        timeToPromisifier(0.3).then({ (_) in
            resolved = true
        })

        // (3) post condition
        do {
            let time = dispatch_time(DISPATCH_TIME_NOW, Int64(0.5 * Double(NSEC_PER_SEC)))

            dispatch_after(time, kOnePromiseTestsQueue, {
                XCTAssertTrue(resolved)
                expectation.fulfill()
            })
        }

        self.waitForExpectationsWithTimeout(3.0, handler: nil)
    }
}

// MARK: Deprecated APIs
extension OnePromiseTests {
    func testDeperecatedAPIs() {
        let expectation1 = self.expectationWithDescription("done 1")
        let expectation2 = self.expectationWithDescription("done 2")

        let promise1 = Promise<Int> { (promise) -> Void in
            dispatch_async(kOnePromiseTestsQueue, {
                promise.fulfill(100)
            })
        }

        let promise2 = Promise<Int> { (promise) -> Void in
            dispatch_async(kOnePromiseTestsQueue, {
                promise.reject(self.generateRandomError())
            })
        }

        promise1.then({ (value) in
            expectation1.fulfill()
            XCTAssertEqual(value, 100)
        })
        promise2.caught({ (_) in
            expectation2.fulfill()
        })

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

