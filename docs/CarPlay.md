# Muwa CarPlay

The audio CarPlay scene uses CPListTemplate, CPTabBarTemplate and Apple's
CPNowPlayingTemplate. It shares PlayerManager, LibraryStore, the queue and
MPRemoteCommandCenter with the phone. Catalog, favorites and recent listening
are native CarPlay lists. It does not render a web page.

Physical CarPlay distribution requires Apple Developer approval for the audio
entitlement `com.apple.developer.carplay-audio`. The unsigned test IPA does not
claim that approval. Add the approved entitlement to the distribution target
and sign with a matching provisioning profile before testing a car/head unit.

Use the CarPlay external display in Xcode Simulator with a CarPlay-enabled
development signing configuration to review the real system templates. Phone
screenshots are not CarPlay screenshots; missing external-display captures
must be reported, not replaced with a generated mockup.
