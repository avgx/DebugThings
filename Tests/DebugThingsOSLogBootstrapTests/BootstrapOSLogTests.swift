import DebugThings
import Logging
import Testing

@Test
func bootstrapOSLogWithoutLevelDoesNotCrash() {
    DebugThings.bootstrapOSLog(subsystem: "com.debugthings.tests")
    let logger = Logger(label: "bootstrap-oslog-smoke")
    logger.info("bootstrap-oslog-smoke-marker")
}
