import XCTest

class PerformanceTests: XCTestCase {

    func testScalability() {
        let N = 10000
        let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)

        var promises: [Promise<Int>] = []

        for _ in 0..<N {
            promises.append(Promise())
        }

        self.measureBlock {
            let semaphore = dispatch_semaphore_create(0);
            promises.removeAll(keepCapacity: true)

            for _ in 0..<N {
                promises.append(Promise<Int>())
            }

            for i in 0..<N {
                dispatch_async(queue, { () -> Void in
                    promises[i].fulfill(i)
                })
            }

            Promise.all(queue, promises)
                .finally(queue, {
                    dispatch_semaphore_signal(semaphore)
                })

            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        }
    }

}
