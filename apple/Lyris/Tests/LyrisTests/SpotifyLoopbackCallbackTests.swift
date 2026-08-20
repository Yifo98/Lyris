import XCTest
@testable import Lyris

final class SpotifyLoopbackCallbackTests: XCTestCase {
    func testCallbackRoutePreservesConfiguredPortAndQuery() throws {
        let route = try SpotifyLoopbackCallbackRoute(port: 43_821)

        let url = try XCTUnwrap(
            route.callbackURL(forRequestTarget: "/oauth/callback?code=fixture&state=expected")
        )

        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:43821/oauth/callback?code=fixture&state=expected")
        XCTAssertTrue(route.accepts(url))
    }

    func testCallbackRouteRejectsWrongPathAndNetworkPathReference() throws {
        let route = try SpotifyLoopbackCallbackRoute(
            port: 43_821,
            expectedPath: "/oauth/spotify-return"
        )
        let wrongPath = try XCTUnwrap(
            route.callbackURL(forRequestTarget: "/oauth/callback?code=fixture")
        )

        XCTAssertFalse(route.accepts(wrongPath))
        XCTAssertNil(route.callbackURL(forRequestTarget: "//example.com/oauth/spotify-return"))
    }
}
