import AvatarServiceClient
import XCTest

final class AvatarServiceClientTests: XCTestCase {
    private final class TokenProvider: AvatarServiceTokenProviding {
        func avatarServiceBearerToken() async throws -> String? {
            "test-token"
        }
    }

    private final class MockURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = Self.handler else {
                self.client?.urlProtocol(self, didFailWithError: AvatarServiceClientError.invalidResponse)
                return
            }

            do {
                let (response, data) = try handler(self.request)
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {
        }
    }

    override func tearDown() {
        Self.MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testGetAvatarsUsesBaseURLAndBearerToken() async throws {
        let client = self.makeClient(baseURL: URL(string: "https://avatar.example.test/api")!)

        Self.MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://avatar.example.test/api/avatars")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"{"avatars":[{"id":"avatar-1","paramsJSON":"{}","displayName":"Base","updatedAt":"2026-04-29"}]}"#.utf8)
            )
        }

        let avatars = try await client.getAvatars()

        XCTAssertEqual(avatars, [
            AvatarServiceAvatar(
                id: "avatar-1",
                paramsJSON: "{}",
                displayName: "Base",
                updatedAt: "2026-04-29"
            )
        ])
    }

    func testGetAvatarsDecodesRawArrayResponse() async throws {
        let client = self.makeClient(baseURL: URL(string: "https://avatar.example.test")!)

        Self.MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"[{"id":"avatar-2"}]"#.utf8)
            )
        }

        let avatars = try await client.getAvatars()

        XCTAssertEqual(avatars, [AvatarServiceAvatar(id: "avatar-2")])
    }

    func testGetAvatarsThrowsForUnexpectedStatusCode() async throws {
        let client = self.makeClient(baseURL: URL(string: "https://avatar.example.test")!)

        Self.MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        do {
            _ = try await client.getAvatars()
            XCTFail("Expected request to fail.")
        } catch AvatarServiceClientError.unexpectedStatusCode(503) {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeClient(baseURL: URL) -> AvatarServiceHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]

        return AvatarServiceHTTPClient(
            configuration: AvatarServiceConfiguration(baseURL: baseURL),
            tokenProvider: TokenProvider(),
            urlSession: URLSession(configuration: configuration)
        )
    }
}
