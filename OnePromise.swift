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

public enum PromiseState<T> {
    case Pending
    case Fulfilled(T)
    case Rejected(NSError)
}

public class Promise<T> {

    public typealias ValueType = T

    private var state: PromiseState<ValueType> = .Pending

    private var onFulfilled: [(ValueType) -> Void] = []

    private var onRejected: [(NSError) -> Void] = []

    public init() {

    }

    public func then<U>(onFulfilled: (ValueType) -> Promise<U>, _ onRejected: ((NSError) -> Void)? = nil) -> Promise<U>
    {
        return Promise<U>({ (nextPromise) -> Void in
            self.appendOnFulfilled(nextPromise, onFulfilled)

            if let onRejected = onRejected {
                self.appendOnRejected(nextPromise, onRejected)
            }
        })
    }

    public func then<U>(onFulfilled: (ValueType) -> U, _ onRejected: ((NSError) -> Void)? = nil) -> Promise<U>
    {
        return Promise<U>({ (nextPromise) -> Void in
            self.appendOnFulfilled(nextPromise, onFulfilled)

            if let onRejected = onRejected {
                self.appendOnRejected(nextPromise, onRejected)
            }
        })
    }

    public func then(onFulfilled: ((ValueType) -> T)?, _ onRejected: ((NSError) -> Void)? = nil) -> Promise<T>
    {
        return Promise<T>({ (nextPromise) -> Void in
            if let onFulfilled = onFulfilled {
                self.appendOnFulfilled(nextPromise, onFulfilled)
            }

            if let onRejected = onRejected {
                self.appendOnRejected(nextPromise, onRejected)
            }
        })
    }

    private func appendOnFulfilled<U>(nextPromise: Promise<U>, _ onFulfilled: ValueType -> Promise<U>) {
        self.onFulfilled.append({ (value) -> Void in
            onFulfilled(value).then(nextPromise.fulfill)
        })
    }

    private func appendOnFulfilled<U>(nextPromise: Promise<U>, _ onFulfilled: ValueType -> U) {
        self.onFulfilled.append({ (value) -> Void in
            nextPromise.fulfill(onFulfilled(value))
        })
    }

    private func appendOnRejected<U>(nextPromise: Promise<U>, _ onRejected: NSError -> Void) {
        self.onRejected.append({ (error) -> Void in
            onRejected(error)
            nextPromise.reject(error)
        })
    }

    public func fulfill(value: ValueType) {
        self.state = .Fulfilled(value)

        for cb in self.onFulfilled {
            cb(value)
        }
    }

    public func reject(error: NSError) {
        self.state = .Rejected(error)

        for cb in self.onRejected {
            cb(error)
        }
    }
}

extension Promise {
    convenience init(_ block: (Promise) -> Void) {
        self.init()
        block(self)
    }
}