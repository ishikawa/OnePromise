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

// For thread safety
private var syncQueueTag = 0xfa9

private let syncQueue: dispatch_queue_t = {
    let q = dispatch_queue_create("jp.ko9.OnePromise.sync", DISPATCH_QUEUE_SERIAL)

    dispatch_queue_set_specific(q, &syncQueueTag, &syncQueueTag, nil)

    return q
}()

/**
    Perform given `block` in serial queue. Reentrant, dead lock free.
*/
private func performSync(block: () -> Void) {
    if dispatch_get_specific(&syncQueueTag) == nil {
        dispatch_sync(syncQueue, block)
    }
    else {
        block()
    }
}


public class Promise<T> {

    public typealias ValueType = T

    private var state: PromiseState<ValueType> = .Pending

    private var fulfillCallbacks: [(ValueType) -> Void] = []

    private var rejectCallbacks: [(NSError) -> Void] = []

    public init() {

    }

    public convenience init(block: Promise<T> -> Void) {
        self.init()
        block(self)
    }

    public func then<U>(onFulfilled: ValueType throws -> Promise<U>, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        return self.then(dispatch_get_main_queue(), onFulfilled, onRejected)
    }

    public func then<U>(onFulfilled: ValueType throws -> U, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        return self.then(dispatch_get_main_queue(), onFulfilled, onRejected)
    }

    public func then(onFulfilled: (ValueType throws -> T)?, _ onRejected: (NSError -> Void)? = nil) -> Promise<T> {
        return self.then(dispatch_get_main_queue(), onFulfilled, onRejected)
    }

    public func then<U>(dispatchQueue: dispatch_queue_t, _ onFulfilled: ValueType throws -> Promise<U>, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        let nextPromise = Promise<U>()

        performSync {
            self.append(dispatchQueue, nextPromise: nextPromise, onFulfilled: onFulfilled)
            self.append(dispatchQueue, nextPromise: nextPromise, onRejected: onRejected)
        }

        return nextPromise
    }

    public func then<U>(dispatchQueue: dispatch_queue_t, _ onFulfilled: ValueType throws -> U, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        let nextPromise = Promise<U>()

        performSync {
            self.append(dispatchQueue, nextPromise: nextPromise, onFulfilled: onFulfilled)
            self.append(dispatchQueue, nextPromise: nextPromise, onRejected: onRejected)
        }

        return nextPromise
    }

    public func then(dispatchQueue: dispatch_queue_t, _ onFulfilled: (ValueType throws -> T)?, _ onRejected: (NSError -> Void)? = nil) -> Promise<T> {
        // If onFulfilled is not nil, the compiler should choose generic function.
        assert( onFulfilled == nil )

        let nextPromise = Promise<T>()

        performSync {
            self.append(dispatchQueue, nextPromise: nextPromise, onFulfilled: { $0 })
            self.append(dispatchQueue, nextPromise: nextPromise, onRejected: onRejected)
        }

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
            performSync {
                self.fulfillCallbacks.append(onFulfilledAsync)
            }
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
            performSync {
                self.fulfillCallbacks.append(onFulfilledAsync)
            }
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
            performSync {
                self.rejectCallbacks.append(onRejectedAsync)
            }
        case .Fulfilled(_):
            return
        case .Rejected(let error):
            onRejectedAsync(error)
        }
    }

    public func fulfill(value: ValueType) {
        performSync {
            if case .Pending = self.state {
                self.state = .Fulfilled(value)

                for cb in self.fulfillCallbacks {
                    cb(value)
                }

                self.fulfillCallbacks.removeAll(keepCapacity: false)
            }
        }
    }

    public func reject(error: NSError) {
        performSync {
            if case .Pending = self.state {
                self.state = .Rejected(error)

                for cb in self.rejectCallbacks {
                    cb(error)
                }

                self.rejectCallbacks.removeAll(keepCapacity: false)
            }
        }
    }
}

// MARK: CustomStringConvertible
extension Promise: CustomStringConvertible {
    public var description: String {
        return "Promise (\(state))"
    }
}

// MARK: fail (catch)
extension Promise {
    /**
    `fail` is sugar, equivalent to `promise.then(nil, onRejected)`.
    
    Most other Promise libraries have `catch` method, which is reserved
    keyword in Swift 2.0.
    */
    public func fail(dispatchQueue: dispatch_queue_t, _ onRejected: (NSError) -> Void) -> Promise<ValueType> {
        return self.then(dispatchQueue, nil, onRejected)
    }

    public func fail(onRejected: (NSError) -> Void) -> Promise<ValueType> {
        return self.fail(dispatch_get_main_queue(), onRejected)
    }
}

// MARK: fin (finally)
extension Promise {

    /**
    
    `fin` will be invoked regardless of the promise is fulfilled or rejected, allows you to
    observe either fulfillment or rejection of the promise.

    - parameter callback
    - returns:  A Promise which will be resolved with the same fulfillment value or
                rejection reason as receiver.

    ### Limitations

    [Promises/A+](https://promisesaplus.com/#notes) allows `onRejected` returns a value or Promise,
    or throws error. OnePromise, however, `onRejected` signature is `(NSError) -> Void`.
    Because of this, we can not implement `finally()` method like
    [Q](https://github.com/kriskowal/q/wiki/API-Reference#promisefinallycallback).

    ### TODO

    If `callback` returns a promise, the resolution of the returned promise will be delayed until
    the promise returned from `callback` is finished.
    */
    public func fin(dispatchQueue: dispatch_queue_t, _ callback: () -> Void) -> Promise<ValueType> {
        return self.then(dispatchQueue,
            { (value) -> ValueType in
                callback()
                return value
            },
            { (error: NSError) in
                callback()
            })
    }

    public func fin(callback: () -> Void) -> Promise<ValueType> {
        return fin(dispatch_get_main_queue(), callback)
    }
}
