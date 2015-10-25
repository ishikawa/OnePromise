import XCTest

class PerformanceTests: XCTestCase {

    func testFulfillPerformance() {
        let N = 10000
        let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)

        self.measureMetrics(XCTestCase.defaultPerformanceMetrics(), automaticallyStartMeasuring: false) {
            let semaphore = dispatch_semaphore_create(0);
            var promises: [Promise<Int>] = []

            for _ in 0..<N {
                promises.append(Promise<Int>())
            }

            Promise.all(queue, promises)
                .finally(queue, {
                    dispatch_semaphore_signal(semaphore)
                })

            self.startMeasuring()

            for i in 0..<N {
                dispatch_async(queue, { () -> Void in
                    promises[i].fulfill(i)
                })
            }

            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
            self.stopMeasuring()
        }
    }
}
