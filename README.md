# OnePromise


[![CI Status](https://travis-ci.org/ishikawa/OnePromise.svg?branch=master)](https://travis-ci.org/ishikawa/OnePromise?branch=master)
[![Version](https://img.shields.io/cocoapods/v/OnePromise.svg?style=flat)](http://cocoapods.org/pods/OnePromise)
[![License](https://img.shields.io/cocoapods/l/OnePromise.svg?style=flat)](http://cocoapods.org/pods/OnePromise)
[![Platform](https://img.shields.io/cocoapods/p/OnePromise.svg?style=flat)](http://cocoapods.org/pods/OnePromise)

One of the Promises in Swift world just for fun :-)

## Features

- Swift 2.0
- No dependencies and fits into one file
- 100% test coverage

## Installation

1. Copy `OnePromise.swift` into your project.
2. The `Promise` class is one and only one public. If you dislike, rename it as you want.
3. Your project enforces "100% test coverage"?? Copy `OnePromiseTests.swift`. Please remove `import OnePromise` line.

## Installation (CocoaPods)

OnePromise is also available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
platform :ios, "8.0"
use_frameworks!

pod "OnePromise"
```

In order to use CocoaPods, you must explicity include `use_frameworks!` and specify
`platform :ios` version to 8.0 at minimum (though OnePromise works on iOS7).

Read [CocoaPods blog entry](http://blog.cocoapods.org/CocoaPods-0.36/) for
more details.

## Author

Takanori Ishikawa

## License

MIT
