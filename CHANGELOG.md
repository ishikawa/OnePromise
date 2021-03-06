# CHANGELOG

**IMPORTANT: Version 0.y.z is for initial develpment. Anything may change at any time. The public API should not be considered stable.**

## 0.7.0

- `.tap` method (#26)
- If the callback passed to `.finally` returns a promise, the resolution of the returned promise will be delayed until the promise returned from callback is resolved. (#25)
- FIX: `Promise.all` should returns array with fulfillment values at respective positions to the original array. (#24)
- Error handling with ErrorType. `.reject` and `.caught` now accept `ErrorType` instance. (#23)

## 0.6.0

- Add `Promise.delay()`
- More API documentation (inline comments)
- Error handling with `ErrorType`

## 0.5.1

- Add deprecated APIs tests.
- Add missing `public` in some APIs.
- To prevent forgetting `public`, the test target depends OnePromise.framework.

## 0.5.0

- Remove `then(nil, onRejected)` syntax to solve type inference problem. You can use `caught(onRejected)` to omit fulfillment handler.
- Deprecate `Promise#fulfill(value)` and `Promise#reject(error)` in favor of `Promise { (fulfill, reject) in ... }` initialization method. These methods will be dropped in a future version.

## 0.4.0

- Performance improvement
- `Promise.resolve(value)` and `Promise.reject(error)`
- `Promise.all(values)` and `Promise.join(value1, value2)` to combine multiple promises

## 0.3.0

- Error propagation from onFulfill callback
- Fix iOS7 compatibility issues
- Add `caught` and `finally` methods.

## 0.2.1

- Update Podfile.lock
- Move test files into top directory

## 0.2.0

Bug fixes and more tests.

- Fixed: Promise resolution is not propagated to child promises
- 100% Test Coverage

## 0.1.0

Initial release.
