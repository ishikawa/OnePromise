// The MIT License (MIT)
//
// Copyright (c) 2015 Takanori Ishikawa
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

private enum PromiseState<T>: CustomStringConvertible {
    case Pending
    case Fulfilled(T)
    case Rejected(NSError)

    var description: String {
        switch self {
        case .Pending:
            return "Pending"
        case .Fulfilled(_):
            return "Fulfilled"
        case .Rejected(_):
            return "Rejected"
        }
    }
}

/**

From [Promises/A+](https://promisesaplus.com) specification:

>A _promise_ represents the eventual result of an asynchronous operation. The primary way of
interacting with a promise is through its `then` method, which registers callbacks to receive either
a promise's value or the reason why promise cannot be fulfilled.

Suppose you have the API which takes callbacks function like:

    func invokeRpc(method: String, params: [String:AnyObject], onComplete: ([String:AnyObject]) -> Void, onError: (NSError) -> Void) {...}

How to create a promise invokes this function:

    let promise = Promise { (fulfill, reject) in
        self.invokeRpc("echo.hello", params: [ "greeting": "hi" ], onComplete: fulfill, onError: reject)
    }

Then you can receive a response (or error) from this promise:

    promise
        .then({ (response) in
            ...
        })
        .caught({ (error) in
            fatalError("Failed: \(error)")
        })

*/
public class Promise<T> {

    public typealias ValueType = T

    private var state: PromiseState<ValueType> = .Pending

    private var fulfillCallbacks: [(ValueType) -> Void] = []

    private var rejectCallbacks: [(NSError) -> Void] = []

    /// Allow the execution of just one thread from many others.
    private let mutex = dispatch_semaphore_create(1)

    @available(*, deprecated, message="It will be dropped from a future version.")
    public convenience init() {
        self.init({ (_, _) in })
    }

    @available(*, deprecated, message="It will be dropped from a future version.")
    public convenience init(block: Promise<T> -> Void) {
        self.init()
        block(self)
    }

    /**

    Create a new promise. The `block` will receive functions fulfill and reject as its arguments
    which can be called to fulfill or reject the created promise.

    */
    public init(_ block: (ValueType -> Void, NSError -> Void) throws -> Void) {
        do {
            try block(self.doFulfill, self.doReject)
        }
        catch let error as NSError {
            self.doReject(error)
        }
    }

    /**

    Creates a new promise instance, and return it and fulfill, reject function.

    You can use `deferred` method to create a new promise, and determine when this promise should be
    fulfilled or rejected.

        let (promise, fulfill, reject) = Promise<Int>.deferred()

        dispatch_async(dispatch_get_main_queue()) {
            fulfill(199)
        }

    `Promise.deferred()` names the individual elements in a tuple it return.

        let deferred = Promise<Int>.deferred()

        dispatch_async(dispatch_get_main_queue()) {
            deferred.fulfill(199)
        }
    */
    public class func deferred() -> (promise: Promise<T>, fulfill: ValueType -> Void, reject: NSError -> Void) {
        var fulfill: (ValueType -> Void)!
        var reject: (NSError -> Void)!

        let promise = Promise<T> {
            fulfill = $0
            reject  = $1
        }

        return (promise: promise, fulfill: fulfill, reject: reject)
    }

    /// Same as `then(dispatch_get_main_queue(), onFulfilled, onRejected)`
    public func then<U>(onFulfilled: ValueType throws -> Promise<U>, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        return self.then(dispatch_get_main_queue(), onFulfilled, onRejected)
    }

    /// Same as `then(dispatch_get_main_queue(), onFulfilled, onRejected)`
    public func then<U>(onFulfilled: ValueType throws -> U, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        return self.then(dispatch_get_main_queue(), onFulfilled, onRejected)
    }

    /**
    Register callback to receive fulfillment/rejection value.

    - Returns: A new promise chained from the promise returned from `onFulfilled` handler
    */
    public func then<U>(dispatchQueue: dispatch_queue_t, _ onFulfilled: ValueType throws -> Promise<U>, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        let deferred = Promise<U>.deferred()

        dispatch_semaphore_wait(self.mutex, DISPATCH_TIME_FOREVER)
        do {
            self.appendP(dispatchQueue, onFulfilled: onFulfilled, nextFulfill: deferred.fulfill, nextReject: deferred.reject)
            self.appendR(dispatchQueue, onRejected: onRejected, nextReject: deferred.reject)
        }
        dispatch_semaphore_signal(self.mutex)

        return deferred.promise
    }

    /**
    Register callback to receive fulfillment/rejection value.

    - Returns: A new promise
    */
    public func then<U>(dispatchQueue: dispatch_queue_t, _ onFulfilled: ValueType throws -> U, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        let deferred = Promise<U>.deferred()

        dispatch_semaphore_wait(self.mutex, DISPATCH_TIME_FOREVER)
        do {
            self.appendF(dispatchQueue, onFulfilled: onFulfilled, nextFulfill: deferred.fulfill, nextReject: deferred.reject)
            self.appendR(dispatchQueue, onRejected: onRejected, nextReject: deferred.reject)
        }
        dispatch_semaphore_signal(self.mutex)

        return deferred.promise
    }

    private func appendP<U>(dispatchQueue: dispatch_queue_t,
        onFulfilled: ValueType throws -> Promise<U>,
        nextFulfill: U -> Void,
        nextReject: NSError -> Void)
    {
        let onFulfilledAsync = { (value: ValueType) -> Void in
            dispatch_async(dispatchQueue, {
                do {
                    try onFulfilled(value).then(dispatchQueue, nextFulfill, nextReject)
                }
                catch let error as NSError {
                    nextReject(error)
                }
            })
        }

        switch self.state {
        case .Pending:
            self.fulfillCallbacks.append(onFulfilledAsync)
        case .Fulfilled(let value):
            onFulfilledAsync(value)
        case .Rejected(_):
            return
        }
    }

    private func appendF<U>(dispatchQueue: dispatch_queue_t,
        onFulfilled: ValueType throws -> U,
        nextFulfill: U -> Void,
        nextReject: NSError -> Void)
    {
        let onFulfilledAsync = { (value: ValueType) -> Void in
            dispatch_async(dispatchQueue, {
                do {
                    nextFulfill(try onFulfilled(value))
                } catch let error as NSError {
                    nextReject(error)
                }
            })
        }

        switch self.state {
        case .Pending:
            self.fulfillCallbacks.append(onFulfilledAsync)
        case .Fulfilled(let value):
            onFulfilledAsync(value)
        case .Rejected(_):
            return
        }
    }

    private func appendR(dispatchQueue: dispatch_queue_t,
        onRejected: (NSError -> Void)?,
        nextReject: NSError -> Void)
    {
        let onRejectedAsync = { (error: NSError) -> Void in
            dispatch_async(dispatchQueue, {
                onRejected?(error)
                nextReject(error)
            })
        }

        switch self.state {
        case .Pending:
            self.rejectCallbacks.append(onRejectedAsync)
        case .Fulfilled(_):
            return
        case .Rejected(let error):
            onRejectedAsync(error)
        }
    }

    @available(*, deprecated, message="It will be dropped from a future version. Use initialization block or Promise.deferred instead")
    public func fulfill(value: ValueType) {
        return self.doFulfill(value)
    }

    @available(*, deprecated, message="It will be dropped from a future version. Use initialization block or Promise.deferred instead")
    public func reject(error: NSError) {
        return self.doReject(error)
    }

    private func doFulfill(value: ValueType) {
        dispatch_semaphore_wait(self.mutex, DISPATCH_TIME_FOREVER)
        do {
            if case .Pending = self.state {
                self.state = .Fulfilled(value)

                for cb in self.fulfillCallbacks {
                    cb(value)
                }

                self.fulfillCallbacks.removeAll(keepCapacity: false)
                self.rejectCallbacks.removeAll(keepCapacity: false)
            }
        }
        dispatch_semaphore_signal(self.mutex)
    }

    private func doReject(error: NSError) {
        dispatch_semaphore_wait(self.mutex, DISPATCH_TIME_FOREVER)
        do {
            if case .Pending = self.state {
                self.state = .Rejected(error)

                for cb in self.rejectCallbacks {
                    cb(error)
                }

                self.fulfillCallbacks.removeAll(keepCapacity: false)
                self.rejectCallbacks.removeAll(keepCapacity: false)
            }
        }
        dispatch_semaphore_signal(self.mutex)
    }
}

// MARK: CustomStringConvertible
extension Promise: CustomStringConvertible {
    public var description: String {
        return "Promise (\(state))"
    }
}

// =====================================================================
// MARK: - Utility
// =====================================================================

extension Promise {
    // -----------------------------------------------------------------
    // MARK: resolve and reject
    // -----------------------------------------------------------------

    /// Returns the `promise`.
    public class func resolve(promise: Promise<ValueType>) -> Promise<ValueType> {
        return promise
    }

    /// Creates a promise will be immediately resolved with given `value`.
    public class func resolve(value: ValueType) -> Promise<ValueType> {
        return Promise<ValueType> { (fulfill, _) -> Void in
            fulfill(value)
        }
    }

    /// Creates a promise that is rejected with given error.
    public class func reject(error: NSError) -> Promise<ValueType> {
        return Promise<ValueType> { (_, reject) -> Void in
            reject(error)
        }
    }

    /// Same as `reject(err as NSError)`
    public class func reject(error: ErrorType) -> Promise<ValueType> {
        return reject(error as NSError)
    }

    // -----------------------------------------------------------------
    // MARK: caught
    // -----------------------------------------------------------------
    /// `caught` is sugar, equivalent to `promise.then(nil, onRejected)`.
    public func caught(dispatchQueue: dispatch_queue_t, _ onRejected: (NSError) -> Void) -> Promise<ValueType> {
        return self.then(dispatchQueue, { $0 }, onRejected)
    }

    /// Same as `caught(dispatch_get_main_queue(), onRejected)`
    public func caught(onRejected: (NSError) -> Void) -> Promise<ValueType> {
        return self.caught(dispatch_get_main_queue(), onRejected)
    }

    /**

    This is an extension to `.caught` to work with Swift's `ErrorType` instead of `NSError`.
    You can specialize `.caught` method with appropriate `ErrorType` protocol.

        promise
            .caught({ (e: CustomError) in
                ...
            })

    **IMPORTANT: If the error is not conformed with `E`, it will be not handled.**

    */
    public func caught<E: ErrorType>(dispatchQueue: dispatch_queue_t, _ onRejected: (E) -> Void)
        -> Promise<ValueType>
    {
        return self.then(dispatchQueue, { $0 }, { (e: NSError) -> Void in
            // We can't directly convert NSError to E
            let err = e as ErrorType

            if let err = err as? E {
                onRejected(err)
            }
        })
    }

    /// Same as `caught(dispatch_get_main_queue(), onRejected)`
    public func caught<E: ErrorType>(onRejected: (E) -> Void) -> Promise<ValueType> {
        return self.caught(dispatch_get_main_queue(), onRejected)
    }

    // -----------------------------------------------------------------
    // MARK: finally
    // -----------------------------------------------------------------
    /**

    `finally` will be invoked regardless of the promise is fulfilled or rejected, allows you to
    observe either fulfillment or rejection of the promise.

    - parameter callback
    - returns:  A Promise which will be resolved with the same fulfillment value or
    rejection reason as receiver.

    */
    public func finally(dispatchQueue: dispatch_queue_t, _ callback: () -> Void) -> Promise<ValueType> {
        return self.then(dispatchQueue,
            { (value) -> ValueType in
                callback()
                return value
            },
            { (error: NSError) in
                callback()
        })
    }

    /// Same as `finally(dispatch_get_main_queue(), callback)`
    public func finally(callback: () -> Void) -> Promise<ValueType> {
        return finally(dispatch_get_main_queue(), callback)
    }
}

// =====================================================================
// MARK: - Collection
// =====================================================================

extension Promise {
    // -----------------------------------------------------------------
    // MARK: all
    // -----------------------------------------------------------------
    /**

    Returns a promise which is fulfilled when all the promises in `promises` are fulfilled.
    The returned promise's fulfillment value is array of `T`.
    If any promise is rejected, the returned promise is rejected.

    */
    public class func all(dispatchQueue: dispatch_queue_t, _ promises: [Promise<ValueType>]) -> Promise<[ValueType]> {
        let deferred = Promise<[ValueType]>.deferred()

        let lock = dispatch_semaphore_create(1)

        var pending = true
        var values: [T] = []

        for subpromise in promises {
            subpromise.then(dispatchQueue,
                { (value) -> Void in
                    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER)
                    do {
                        if pending {
                            values.append(value)

                            if values.count == promises.count {
                                deferred.fulfill(values)
                                pending = false
                                values.removeAll(keepCapacity: false)
                            }
                        }
                    }
                    dispatch_semaphore_signal(lock)
                },
                { (error) -> Void in
                    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER)
                    do {
                        if pending {
                            deferred.reject(error)
                            pending = false
                            values.removeAll(keepCapacity: false)
                        }
                    }
                    dispatch_semaphore_signal(lock)
                })
        }

        return deferred.promise
    }

    /// Same as `all(dispatch_get_main_queue(), promises)`
    public class func all(promises: [Promise<T>]) -> Promise<[T]> {
        return all(dispatch_get_main_queue(), promises)
    }

    // -----------------------------------------------------------------
    // MARK: join
    // -----------------------------------------------------------------
    /**
    Like `all`, but for multiple discrete promises. `Promise.join(...)` is easier and
    more performant (by reducing internal lock) to use fixed amount of discrete promises.

        Promise.join(promise1, promise2)
            .then({ (v1, v2) -> Void in
                ...
            })
    */
    public class func join<U1>(dispatchQueue: dispatch_queue_t,
        _ promise1: Promise<ValueType>,
        _ promise2: Promise<U1>)
        -> Promise<(ValueType, U1)>
    {
        let deferred = Promise<(ValueType, U1)>.deferred()

        promise1.then(dispatchQueue,
            { (v1) -> Void in
                promise2.then(dispatchQueue, { (v2) -> Void in
                    deferred.fulfill((v1, v2))
                })
            }, deferred.reject)

        promise2.caught(dispatchQueue, deferred.reject)

        return deferred.promise
    }

    /// Same as `Promise.join(dispatch_get_main_queue(), promise1, promise2)`
    public class func join<U1>(
          promise1: Promise<ValueType>,
        _ promise2: Promise<U1>)
        -> Promise<(ValueType, U1)>
    {
        return Promise.join(dispatch_get_main_queue(), promise1, promise2)
    }

    /**

    `Promise.join(...)` for 3 promises.

        Promise.join(promise1, promise2, promise3)
            .then({ (v1, v2, v3) -> Void in
                ...
            })
    */
    public class func join<U1, U2>(dispatchQueue: dispatch_queue_t,
        _ promise1: Promise<ValueType>,
        _ promise2: Promise<U1>,
        _ promise3: Promise<U2>)
        -> Promise<(ValueType, U1, U2)>
    {
        let deferred = Promise<(ValueType, U1, U2)>.deferred()

        promise1.then(dispatchQueue,
            { (v1) -> Void in
                promise2.then(dispatchQueue, { (v2) -> Void in
                    promise3.then(dispatchQueue, { (v3) -> Void in
                        deferred.fulfill((v1, v2, v3))
                    })
                })
            }, deferred.reject)

        promise2.caught(dispatchQueue, deferred.reject)
        promise3.caught(dispatchQueue, deferred.reject)

        return deferred.promise
    }

    /// Same as `Promise.join(dispatch_get_main_queue(), promise1, promise2, promise3)`
    public class func join<U1, U2>(
          promise1: Promise<ValueType>,
        _ promise2: Promise<U1>,
        _ promise3: Promise<U2>)
        -> Promise<(ValueType, U1, U2)>
    {
        return Promise.join(dispatch_get_main_queue(), promise1, promise2, promise3)
    }
}

// =====================================================================
// MARK: - Timer
// =====================================================================
extension Promise {

    // -----------------------------------------------------------------
    // MARK: delay
    // -----------------------------------------------------------------
    /// Returns a promise that will be resolved with given `promise`'s fulfillment value
    /// after `seconds` seconds.
    public class func delay(dispatchQueue: dispatch_queue_t, _ promise: Promise<T>, _ seconds: NSTimeInterval) -> Promise<T> {
        return promise.then(dispatchQueue, { Promise.delay(dispatchQueue, $0, seconds) })
    }

    /// Returns a promise that will be resolved with given `value` after `seconds` seconds.
    public class func delay(dispatchQueue: dispatch_queue_t, _ value: T, _ seconds: NSTimeInterval) -> Promise<T> {
        let delay = seconds * Double(NSEC_PER_SEC)
        let time  = dispatch_time(DISPATCH_TIME_NOW, Int64(delay))

        return Promise<T> { (fulfill, _) -> Void in
            dispatch_after(time, dispatchQueue, {
                fulfill(value)
            })
        }
    }

    /**
    Same as `Promise.delay(self, seconds)`, so you can write:

        promise
            .then({
                ...
            })
            .delay(0.5)
    */
    public func delay(dispatchQueue: dispatch_queue_t, _ seconds: NSTimeInterval) -> Promise<ValueType> {
        return Promise.delay(dispatchQueue, self, seconds)
    }

    /// Same as `Promise.delay(dispatch_get_main_queue(), promise, seconds)`
    public class func delay(promise: Promise<T>, _ seconds: NSTimeInterval) -> Promise<T> {
        return Promise.delay(dispatch_get_main_queue(), promise, seconds)
    }

    /// Same as `Promise.delay(dispatch_get_main_queue(), value, seconds)`
    public class func delay(value: T, _ seconds: NSTimeInterval) -> Promise<T> {
        return Promise.delay(dispatch_get_main_queue(), value, seconds)
    }

    /// Same as `delay(dispatch_get_main_queue(), seconds)`
    public func delay(seconds: NSTimeInterval) -> Promise<ValueType> {
        return self.delay(dispatch_get_main_queue(), seconds)
    }
}
