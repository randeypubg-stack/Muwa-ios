import Foundation

final class CatalogProtocol: URLProtocol {
  nonisolated(unsafe) static var document: String = ""
  nonisolated(unsafe) static var status = 200
  nonisolated(unsafe) static var receivedRequest: URLRequest?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.receivedRequest = request
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(Self.document.utf8)); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
@main struct CatalogChecks {
  @MainActor static func main() async throws {
    let suite="muwa.catalog.audit.\(UUID())", defaults=UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let config=URLSessionConfiguration.ephemeral; config.protocolClasses=[CatalogProtocol.self]; config.httpCookieStorage = nil
    let store=CatalogStore(defaults:defaults,session:URLSession(configuration:config))
    precondition(store.tracks.isEmpty, "Fresh catalog must not require Floot")
    store.installReviewTracks([Track(id:"saved-1",title:"Saved",artist:"Muwa",duration:1,artworkURL:nil,audioURL:BackendConfig.apiBaseURL.appending(path:"saved.wav"))])
    CatalogProtocol.document=#"{"version":1,"tracks":[{"id":"remote-1","title":"Remote","artist":"Muwa","duration":42,"audio":"/_cdn/public/catalog/a/audio.mp3","artwork":null,"captionsRevision":2}]}"#
    await store.refresh(force:true)
    precondition(CatalogProtocol.receivedRequest?.url?.path == "/_api/catalog/tracks" && CatalogProtocol.receivedRequest?.value(forHTTPHeaderField: "Cookie") == nil, "Guest catalog unexpectedly requires a session")
    precondition(store.tracks.count == 1 && store.tracks[0].id == "remote-1" && store.tracks[0].captionsRevision == 2)
    precondition(store.tracks[0].audioURL.absoluteString == "https://93.188.187.96/_cdn/public/catalog/a/audio.mp3")
    precondition(store.track(id:"saved-1") != nil, "Remote refresh discarded metadata for a saved track")
    let offline=CatalogStore(defaults:defaults)
    precondition(offline.tracks == store.tracks && offline.track(id:"saved-1") != nil, "Cache cannot bootstrap offline")
    CatalogProtocol.document=#"{"version":1,"tracks":[{"id":"../invalid","title":"Remote","artist":"Muwa","duration":42,"audio":"https://muwa-app.floot.app/a.mp3","artwork":null,"captionsRevision":1}]}"#
    await store.refresh(force:true); precondition(store.tracks.count == 1, "Malformed response replaced the valid cache")
    CatalogProtocol.status=503; await store.refresh(force:true); precondition(store.tracks.count == 1)
    CatalogProtocol.status=200; CatalogProtocol.document=#"{"version":1,"tracks":[]}"#
    await store.refresh(force:true)
    precondition(store.tracks.isEmpty && store.track(id:"remote-1") != nil)
    precondition(CatalogStore(defaults:defaults).tracks.isEmpty, "Intentional empty catalogue repopulated after restart")
    print("PASS: remote catalogue, relative URLs, offline cache, retained user metadata, invalid/network response and intentional empty catalogue")
  }
}
