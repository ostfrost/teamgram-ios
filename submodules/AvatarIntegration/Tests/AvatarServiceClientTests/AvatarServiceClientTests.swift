import AvatarAuthClient
import AvatarServiceClient
import XCTest

final class AvatarServiceClientTests: XCTestCase {
    private final class TokenProvider: AvatarServiceTokenProviding {
        func avatarBearerToken() async throws -> String? {
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

    func testListAvatarsUsesBaseURLAndBearerToken() async throws {
        let client = self.makeAvatarClient(baseURL: URL(string: "https://avatar.example.test/api/v1")!)

        Self.MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://avatar.example.test/api/v1/avatars")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "avatars": [
                    {
                      "id": 42,
                      "userId": 7,
                      "name": "Base",
                      "type": "human",
                      "paramsJson": {"morphs": {"face_shape": 0.25}},
                      "images": [],
                      "createdAt": "2026-04-29T12:00:00Z",
                      "updatedAt": "2026-04-29T12:01:00Z"
                    }
                  ]
                }
                """.utf8)
            )
        }

        let avatars = try await client.listAvatars()

        XCTAssertEqual(avatars.count, 1)
        XCTAssertEqual(avatars[0].id, 42)
        XCTAssertEqual(avatars[0].userId, 7)
        XCTAssertEqual(avatars[0].name, "Base")
        XCTAssertEqual(avatars[0].type, .human)
        XCTAssertEqual(avatars[0].paramsJson["morphs"], .object(["face_shape": .number(0.25)]))
    }

    func testUpdateAvatarEncodesParamsJson() async throws {
        let client = self.makeAvatarClient(baseURL: URL(string: "https://avatar.example.test/api/v1")!)

        Self.MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.absoluteString, "https://avatar.example.test/api/v1/avatars/42")

            let body = try XCTUnwrap(Self.bodyData(from: request))
            let bodyObject = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(bodyObject?["name"] as? String, "Updated")
            XCTAssertEqual(bodyObject?["type"] as? String, "human")
            XCTAssertNotNil(bodyObject?["paramsJson"] as? [String: Any])

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Self.avatarResponse(id: 42, name: "Updated")
            )
        }

        let avatar = try await client.updateAvatar(
            id: 42,
            name: "Updated",
            type: .human,
            paramsJson: ["skin": .string("#C68642")]
        )

        XCTAssertEqual(avatar.name, "Updated")
    }

    func testAnalyzeWithImageUsesMultipartAndFiveSecondTimeout() async throws {
        let client = self.makeAvatarClient(baseURL: URL(string: "https://avatar.example.test/api/v1")!)

        Self.MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://avatar.example.test/api/v1/avatars/analyze/with-image")
            XCTAssertEqual(request.timeoutInterval, 5.0)
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let body = try XCTUnwrap(Self.bodyData(from: request))
            XCTAssertTrue(String(data: body, encoding: .utf8)?.contains("name=\"image\"; filename=\"selfie.jpg\"") == true)

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "preset": {
                    "type": "human",
                    "morphs": {"face_shape": 0.1},
                    "colors": {"skin": "#C68642"},
                    "suggestedHairStyleId": "short-01"
                  },
                  "confidence": 0.8,
                  "analyzer": "rekognition"
                }
                """.utf8)
            )
        }

        let response = try await client.analyzeAvatarWithImage(Data([1, 2, 3]), fileName: "selfie.jpg", mimeType: "image/jpeg")

        XCTAssertEqual(response.analyzer, "rekognition")
        XCTAssertEqual(response.preset.suggestedHairStyleId, "short-01")
    }

    func testUnexpectedStatusDecodesProblemDetail() async throws {
        let client = self.makeAvatarClient(baseURL: URL(string: "https://avatar.example.test/api/v1")!)

        Self.MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/problem+json"]
                )!,
                Data(#"{"type":"FACE_ANALYZER_UNAVAILABLE","title":"Service Unavailable","status":503}"#.utf8)
            )
        }

        do {
            _ = try await client.listAvatars()
            XCTFail("Expected request to fail.")
        } catch AvatarServiceClientError.unexpectedStatusCode(503, let problem) {
            XCTAssertEqual(problem?.type, "FACE_ANALYZER_UNAVAILABLE")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthSignInReturnsAuthorizedSession() async throws {
        let client = self.makeAuthClient(baseURL: URL(string: "https://auth.example.test/api/v1")!)

        Self.MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://auth.example.test/api/v1/auth/sign-in")

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"status":"authorized","token":"jwt","expiresIn":3600,"userId":99}"#.utf8)
            )
        }

        let step = try await client.signIn(phoneNumber: "+15555550100", phoneCodeHash: "hash", phoneCode: "11111")

        XCTAssertEqual(step, .authorized(AvatarAuthorizedSession(token: "jwt", expiresIn: 3600, userId: 99)))
    }

    func testAuthSignInReturnsSignUpRequired() async throws {
        let client = self.makeAuthClient(baseURL: URL(string: "https://auth.example.test/api/v1")!)

        Self.MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"status":"sign_up_required","phoneCodeHash":"next-hash"}"#.utf8)
            )
        }

        let step = try await client.signIn(phoneNumber: "+15555550100", phoneCodeHash: "hash", phoneCode: "11111")

        XCTAssertEqual(step, .signUpRequired(phoneCodeHash: "next-hash"))
    }

    func testAuthSignInReturnsPasswordRequired() async throws {
        let client = self.makeAuthClient(baseURL: URL(string: "https://auth.example.test/api/v1")!)

        Self.MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"status":"password_required","passwordHash":"pw-hash","userId":99}"#.utf8)
            )
        }

        let step = try await client.signIn(phoneNumber: "+15555550100", phoneCodeHash: "hash", phoneCode: "11111")

        XCTAssertEqual(step, .passwordRequired(passwordHash: "pw-hash", userId: 99))
    }

    private func makeAvatarClient(baseURL: URL) -> AvatarServiceHTTPClient {
        AvatarServiceHTTPClient(
            configuration: AvatarServiceConfiguration(baseURL: baseURL),
            tokenProvider: TokenProvider(),
            urlSession: self.makeURLSession()
        )
    }

    private func makeAuthClient(baseURL: URL) -> AvatarAuthHTTPClient {
        AvatarAuthHTTPClient(
            configuration: AvatarAuthConfiguration(baseURL: baseURL),
            urlSession: self.makeURLSession()
        )
    }

    private func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func avatarResponse(id: Int64, name: String) -> Data {
        Data("""
        {
          "id": \(id),
          "userId": 7,
          "name": "\(name)",
          "type": "human",
          "paramsJson": {},
          "images": [],
          "createdAt": "2026-04-29T12:00:00Z",
          "updatedAt": "2026-04-29T12:01:00Z"
        }
        """.utf8)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer {
            stream.close()
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read < 0 {
                return nil
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
