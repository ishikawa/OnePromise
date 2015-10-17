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

public enum PromiseState<T>: CustomStringConvertible {
    case Pending
    case Fulfilled(T)
    case Rejected(NSError)

    public var description: String {
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

    private var onFulfilled: [(ValueType) -> Void] = []

    private var onRejected: [(NSError) -> Void] = []

    public init() {

    }

    public func then<U>(onFulfilled: ValueType -> Promise<U>, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        let nextPromise = Promise<U>()

        performSync {
            self.appendOnFulfilled(nextPromise, onFulfilled)
            self.appendOnRejected(nextPromise, onRejected)
        }

        return nextPromise
    }

    public func then<U>(onFulfilled: ValueType -> U, _ onRejected: (NSError -> Void)? = nil) -> Promise<U> {
        let nextPromise = Promise<U>()

        performSync {
            self.appendOnFulfilled(nextPromise, onFulfilled)
            self.appendOnRejected(nextPromise, onRejected)
        }

        return nextPromise
    }

    public func then(onFulfilled: (ValueType -> T)?, _ onRejected: (NSError -> Void)? = nil) -> Promise<T> {
        let nextPromise = Promise<T>()

        performSync {
            self.appendOnFulfilled(nextPromise, onFulfilled)
            self.appendOnRejected(nextPromise, onRejected)
        }

        return nextPromise
    }

    private func appendOnFulfilled<U>(nextPromise: Promise<U>, _ onFulfilled: ValueType -> Promise<U>) {
        switch self.state {
        case .Pending:
            self.onFulfilled.append({ (value) -> Void in
                onFulfilled(value).then(nextPromise.fulfill)
            })
        case .Fulfilled(let value):
            dispatch_async(dispatch_get_main_queue(), {
                onFulfilled(value).then(nextPromise.fulfill)
            })
        case .Rejected(_):
            return
        }
    }

    private func appendOnFulfilled<U>(nextPromise: Promise<U>, _ onFulfilled: (ValueType -> U)?) {
        if let onFulfilled = onFulfilled {
            switch self.state {
            case .Pending:
                self.onFulfilled.append({ (value) -> Void in
                    nextPromise.fulfill(onFulfilled(value))
                })
            case .Fulfilled(let value):
                dispatch_async(dispatch_get_main_queue(), {
                    nextPromise.fulfill(onFulfilled(value))
                })
            case .Rejected(_):
                return
            }
        }
    }

    private func appendOnRejected<U>(nextPromise: Promise<U>, _ onRejected: (NSError -> Void)?) {
        if let onRejected = onRejected {
            switch self.state {
            case .Pending:
                self.onRejected.append({ (error) -> Void in
                    onRejected(error)
                    nextPromise.reject(error)
                })
            case .Fulfilled(_):
                return
            case .Rejected(let error):
                dispatch_async(dispatch_get_main_queue(), {
                    onRejected(error)
                })
                nextPromise.reject(error)
            }
        }
    }

    public func fulfill(value: ValueType) {
        performSync {
            if case .Pending = self.state {
                self.state = .Fulfilled(value)

                for cb in self.onFulfilled {
                    dispatch_async(dispatch_get_main_queue(), {
                        cb(value)
                    })
                }
            }
            else {
                fatalError("\(self.state) must not transition to any other state.")
            }
        }
    }

    public func reject(error: NSError) {
        performSync {
            if case .Pending = self.state {
                self.state = .Rejected(error)

                for cb in self.onRejected {
                    dispatch_async(dispatch_get_main_queue(), {
                        cb(error)
                    })
                }
            }
            else {
                fatalError("\(self.state) must not transition to any other state.")
            }
        }
    }
}

extension Promise {
    convenience init(_ block: (Promise) -> Void) {
        self.init()
        block(self)
    }
}