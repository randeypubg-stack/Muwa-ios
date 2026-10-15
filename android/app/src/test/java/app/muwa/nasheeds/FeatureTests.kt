package app.muwa.nasheeds
import org.junit.Test
import org.junit.Assert.*
class FeatureTests {
    @Test fun validationDoesNotFakePremium() {assertTrue(FeatureAccess.allowed(false));assertTrue(FeatureAccess.allowed(true));assertFalse(FeatureAccess.premiumRestrictionsEnabled)}
    @Test fun positionFormattingHandlesInvalidPositions() {assertEquals("0:00",formatTime(-1000));assertEquals("1:05",formatTime(65000));assertEquals("10:00",formatTime(600000))}
}
