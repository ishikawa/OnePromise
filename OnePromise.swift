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

*/
public class Promise<T> {

    public typealias ValueType = T

    private var state: PromiseState<ValueType> = .Pending

    private var fulfillCallbacks: [(ValueType) -> Void] = []

    private var rejectCallbacks: [(NSError) -> Void] = []

    /// Allow the execution of just one thread from many others.
    private let mutex = dispatch_semaphore_create(1)

    @available(*, deprecated, message="It will be dropped from a future version.")
    public init() {
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
    public convenience init(_ block: (ValueType -> Void, NSError -> Void) -> Void) {
        self.init()
        block(self.doFulfill, self.doReject)
    }

    /**

    Creates a new promise instance, and return it and fulfill, reject function.

    You can use `deferred` method to create a new promise, and determine when this promise should be
    fulfilled or rejected.

    */
    public class func deferred() -> (Promise<T>, ValueType -> Void, NSError -> Void) {
        var fulfill: (ValueType -> Void)?
        var reject: (NSError -> Void)?

        let promise = Promise<T>({
            (fulfill_, reject_) -> Void in

            fulfill = fulfill_
            reject  = reject_
        })

        return (promise, fulfill!, reject!)
    }

    public func then<U>(onFulfilled: ValueType throws -> Promise<U>, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        return self.then(dispatch_get_main_queue(), onFulfilled, onRejected)
    }

    public func then<U>(onFulfilled: ValueType throws -> U, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        return self.then(dispatch_get_main_queue(), onFulfilled, onRejected)
    }

    public func then<U>(dispatchQueue: dispatch_queue_t, _ onFulfilled: ValueType throws -> Promise<U>, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        let nextPromise = Promise<U>()

        dispatch_semaphore_wait(self.mutex, DISPATCH_TIME_FOREVER)
        do {
            self.append(dispatchQueue, nextPromise: nextPromise, onFulfilled: onFulfilled)
            self.append(dispatchQueue, nextPromise: nextPromise, onRejected: onRejected)
        }
        dispatch_semaphore_signal(self.mutex)

        return nextPromise
    }

    public func then<U>(dispatchQueue: dispatch_queue_t, _ onFulfilled: ValueType throws -> U, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        let nextPromise = Promise<U>()

        dispatch_semaphore_wait(self.mutex, DISPATCH_TIME_FOREVER)
        do {
            self.append(dispatchQueue, nextPromise: nextPromise, onFulfilled: onFulfilled)
            self.append(dispatchQueue, nextPromise: nextPromise, onRejected: onRejected)
        }
        dispatch_semaphore_signal(self.mutex)

        return nextPromise
    }

    private func append<U>(dispatchQueue: dispatch_queue_t, nextPromise: Promise<U>, onFulfilled: ValueType throws -> Promise<U>) {
        let onFulfilledAsync = { (value: ValueType) -> Void in
            dispatch_async(dispatchQueue, {
                do {
                    try onFulfilled(value).then(dispatchQueue, nextPromise.fulfill, nextPromise.reject)
                } catch let error as NSError {
                    nextPromise.reject(error)
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

    private func append<U>(dispatchQueue: dispatch_queue_t, nextPromise: Promise<U>, onFulfilled: ValueType throws -> U) {
        let onFulfilledAsync = { (value: ValueType) -> Void in
            dispatch_async(dispatchQueue, {
                do {
                    let nextValue = try onFulfilled(value)
                    nextPromise.fulfill(nextValue)
                } catch let error as NSError {
                    nextPromise.reject(error)
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

    private func append<U>(dispatchQueue: dispatch_queue_t, nextPromise: Promise<U>, onRejected: (NSError -> Void)?) {
        let onRejectedAsync = { (error: NSError) -> Void in
            dispatch_async(dispatchQueue, {
                onRejected?(error)
                nextPromise.reject(error)
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

// MARK: resolve and reject
extension Promise {
    /**

    Create a promise that is resolved with given value.

    If `value` is a Promise, returns the promise.
    If `value` is not a Promise, returns a promise that is fulfilled with `value`.
    */
    class func resolve(value: Promise<ValueType>) -> Promise<ValueType> {
        return value
    }

    class func resolve(value: ValueType) -> Promise<ValueType> {
        return Promise<ValueType> { $0.fulfill(value) }
    }

    /// Create a promise that is rejected with given error.
    class func reject(error: NSError) -> Promise<ValueType> {
        return Promise<ValueType> { $0.reject(error) }
    }
}

// MARK: catch and finally
extension Promise {
    /// `caught` is sugar, equivalent to `promise.then(nil, onRejected)`.
    public func caught(dispatchQueue: dispatch_queue_t, _ onRejected: (NSError) -> Void) -> Promise<ValueType> {
        return self.then(dispatchQueue, { $0 }, onRejected)
    }

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

    public func caught(onRejected: (NSError) -> Void) -> Promise<ValueType> {
        return self.caught(dispatch_get_main_queue(), onRejected)
    }
    public func finally(callback: () -> Void) -> Promise<ValueType> {
        return finally(dispatch_get_main_queue(), callback)
    }
}

// MARK: Promise.all
extension Promise {
    /**

    Returns a promise which is fulfilled when all the promises in `promises` are fulfilled.
    The returned promise's fulfillment value is array of `T`.
    If any promise is rejected, the returned promise is rejected.

    */
    class func all(promises: [Promise<T>]) -> Promise<[T]> {
        return all(dispatch_get_main_queue(), promises)
    }

    class func all(dispatchQueue: dispatch_queue_t, _ promises: [Promise<T>]) -> Promise<[T]> {
        let promise = Promise<[T]>()

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
                                promise.fulfill(values)
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
                            promise.reject(error)
                            pending = false
                            values.removeAll(keepCapacity: false)
                        }
                    }
                    dispatch_semaphore_signal(lock)
                })
        }
        
        return promise
    }
}

// MARK: Promise.join
extension Promise {
    /**
    Like `all`, but for multiple discrete promises. `Promise.join(...)` is easier and
    more performant (by reducing internal lock) to use fixed amount of discrete promises.

        Promise.join(promise1, promise2)
            .then({ (v1, v2) -> Void in
                ...
            })
    */
    class func join<U1>(
        promise1: Promise<ValueType>,
        _ promise2: Promise<U1>)
        -> Promise<(ValueType, U1)>
    {
        return Promise.join(dispatch_get_main_queue(), promise1, promise2)
    }

    class func join<U1>(dispatchQueue: dispatch_queue_t,
        _ promise1: Promise<ValueType>,
        _ promise2: Promise<U1>)
        -> Promise<(ValueType, U1)>
    {
        let joinPromise = Promise<(ValueType, U1)>()

        promise1.then(dispatchQueue,
            { (v1) -> Void in
                promise2.then(dispatchQueue, { (v2) -> Void in
                    joinPromise.fulfill((v1, v2))
                })
            }, joinPromise.reject)

        promise2.caught(dispatchQueue, joinPromise.reject)

        return joinPromise
    }

    class func join<U1, U2>(
        promise1: Promise<ValueType>,
        _ promise2: Promise<U1>,
        _ promise3: Promise<U2>)
        -> Promise<(ValueType, U1, U2)>
    {
        return Promise.join(dispatch_get_main_queue(), promise1, promise2, promise3)
    }

    class func join<U1, U2>(dispatchQueue: dispatch_queue_t,
        _ promise1: Promise<ValueType>,
        _ promise2: Promise<U1>,
        _ promise3: Promise<U2>)
        -> Promise<(ValueType, U1, U2)>
    {
        let joinPromise = Promise<(ValueType, U1, U2)>()

        promise1.then(dispatchQueue,
            { (v1) -> Void in
                promise2.then(dispatchQueue, { (v2) -> Void in
                    promise3.then(dispatchQueue, { (v3) -> Void in
                        joinPromise.fulfill((v1, v2, v3))
                    })
                })
            }, joinPromise.reject)

        promise2.caught(dispatchQueue, joinPromise.reject)
        promise3.caught(dispatchQueue, joinPromise.reject)

        return joinPromise
    }
}
