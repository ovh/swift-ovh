//
//  OVHAPIWrapperTests.swift
//
//  Copyright (c) 2016, OVH SAS.
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright
//  notice, this list of conditions and the following disclaimer in the
//  documentation and/or other materials provided with the distribution.
//  * Neither the name of OVH SAS nor the
//  names of its contributors may be used to endorse or promote products
//  derived from this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY OVH SAS AND CONTRIBUTORS ``AS IS'' AND ANY
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL OVH SAS AND CONTRIBUTORS BE LIABLE FOR ANY
//  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import XCTest
@testable import OVHAPIWrapper

class OVHAPIWrapperTests: XCTestCase {
    
    // MARK: - Properties
    
    let credentials = NSDictionary(contentsOfFile: Bundle(for: OVHAPIWrapperTests.self).path(forResource: "Credentials", ofType: "plist")!)!
    var applicationKey = ""
    var applicationSecret = ""
    var consumerKey = ""
    let timeout: TimeInterval = 30.0
    let invalidValue = "x"
    
    
    // MARK: - Lifecycle
    
    override func setUp() {
        super.setUp()
        
        // Put setup code here. This method is called before the invocation of each test method in the class.
        applicationKey = credentials["ApplicationKey"] as! String
        applicationSecret = credentials["ApplicationSecret"] as! String
        consumerKey = credentials["ConsumerKey"] as! String
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    
    // MARK: - Tests
    
    func testEndpointVersionAutomaticallySet() {
        let APIEndpoints: [[OVHAPIEndpoint : String]] = [
            [.OVHEU: OVHAPIEndPointVersion.latestOVHEU],
            [.OVHCA: OVHAPIEndPointVersion.latestOVHCA],
            [.kimsufiEU: OVHAPIEndPointVersion.latestKimsufiEU],
            [.kimsufiCA: OVHAPIEndPointVersion.latestKimsufiCA],
            [.soYouStartEU: OVHAPIEndPointVersion.latestSoYouStartEU],
            [.soYouStartCA: OVHAPIEndPointVersion.latestSoYouStartCA],
            [.runabove: OVHAPIEndPointVersion.latestRunabove]
        ]
        
        for APIEndpoint in APIEndpoints {
            let endpoint = APIEndpoint.keys.first!
            let endpointVersion = APIEndpoint[endpoint]!
            let APIWrapper = OVHAPIWrapper(endpoint: endpoint, applicationKey: applicationKey, applicationSecret: applicationSecret)
            let expectedAPIEndpoint = "\(endpoint.rawValue)\(endpointVersion)"
            
            XCTAssertEqual(APIWrapper.endpoint, expectedAPIEndpoint, "Create a wrapper to the API '\(endpoint)' must point to the latest version of this API '\(expectedAPIEndpoint)', but get \(APIWrapper.endpoint).")
        }
    }
    
    func testCallAPIBeforeRequestingCredentialsMustThrowError() {
        let expectation = self.expectation(description: "Calling API before requesting credentials")
        
        let APIWrapper = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: applicationKey, applicationSecret: applicationSecret)
        
        APIWrapper.get("/me") { (result, error, request, response) -> Void in
            XCTAssertTrue(Thread.isMainThread, "\(expectation) must run completion in the main thread.")
            XCTAssertNotNil(error, "\(expectation) must return an error.")
            XCTAssertTrue(error is OVHAPIError, "\(expectation) must return a 'OVHAPIError' as error.")
            
            if let error = error {
                switch error {
                case OVHAPIError.missingConsumerKey: break
                default: XCTFail("\(expectation) must not return error \(error).")
                }
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: timeout, handler: nil)
    }
    
    func testRequestCredentials() {
        checkCredentials()
        
        let expectation = self.expectation(description: "Request credentials")
        
        let APIWrapper = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: applicationKey, applicationSecret: applicationSecret)
        let accessRules = OVHAPIAccessRule.allRights()
        
        APIWrapper.requestCredentials(withAccessRules: accessRules, redirection: "https://www.ovh.com/fr/") { key, validationUrl, error, request, response in
            XCTAssertTrue(Thread.isMainThread, "\(expectation) must run completion in the main thread.")
            XCTAssertNil(error, "\(expectation) must not return an error.")
            XCTAssertNotNil(key, "\(expectation) must return a consumer key.")
            XCTAssertNotNil(validationUrl, "\(expectation) must return a validation url.")
            
            if let key = key {
                XCTAssertTrue(key.characters.count > 0, "\(expectation) must return a valid consumer key.")
            }
            
            if let validationUrl = validationUrl {
                XCTAssertTrue(validationUrl.characters.count > 0, "\(expectation) must return a valid validation url.")
            }
            
            XCTAssertEqual(APIWrapper.consumerKey, key, "\(expectation) must save the consumer key in the API wrapper object.")
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: timeout, handler: nil)
    }
    
    #if os(iOS)
    func testRequestCredentialsWithViewController() {
        checkCredentials()
        
        let expectation = self.expectation(description: "Request credentials with view controller")
        
        let APIWrapper = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: applicationKey, applicationSecret: applicationSecret)
        let accessRules = OVHAPIAccessRule.allRights()
        
        APIWrapper.requestCredentials(withAccessRules: accessRules, redirection: "https://www.ovh.com/fr/") { viewController, error in
            XCTAssertTrue(Thread.isMainThread, "\(expectation) must run completion in the main thread.")
            XCTAssertNil(error, "\(expectation) must not return an error.")
            XCTAssertNotNil(viewController, "\(expectation) must return a view controller.")
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: timeout, handler: nil)
    }
    #else
    func testRequestCredentialsWithViewController() {
        // This method must be redefined for the other OS than iOS
        // because Xcode crashes if it not present at runtime.
    }
    #endif
    
    func testCallAPIWithMissingApplicationKeyMustThrowError() {
        checkEndpointMeWithApplicationKey("", applicationSecret: applicationSecret, consumerKey: consumerKey, expectationDescription: "Calling any API with missing application key")
    }
    
    func testCallAPIWithMissingApplicationSecretMustThrowError() {
        checkEndpointMeWithApplicationKey(applicationKey, applicationSecret: "", consumerKey: consumerKey, expectationDescription: "Calling any API with missing application secret")
    }
    
    func testCallAPIWithMissingConsumerKeyMustThrowError() {
        checkEndpointMeWithApplicationKey(applicationKey, applicationSecret: applicationSecret, consumerKey: nil, expectationDescription: "Calling any API with missing consumer key")
        checkEndpointMeWithApplicationKey(applicationKey, applicationSecret: applicationSecret, consumerKey: "", expectationDescription: "Calling any API with missing consumer key")
    }
    
    func testCallAPIWithWrongApplicationKeyMustReturnError() {
        checkEndpointMeWithApplicationKey(invalidValue, applicationSecret: applicationSecret, consumerKey: consumerKey, expectationDescription: "Call API with wrong application key")
    }
    
    func testCallAPIWithWrongApplicationSecretMustReturnError() {
        checkEndpointMeWithApplicationKey(applicationKey, applicationSecret: invalidValue, consumerKey: consumerKey, expectationDescription: "Call API with wrong application secret")
    }
    
    func testCallAPIWithWrongConsumerKeyMustReturnError() {
        checkEndpointMeWithApplicationKey(applicationKey, applicationSecret: applicationSecret, consumerKey: invalidValue, expectationDescription: "Call API with wrong consumer key")
    }
    
    func testCallAPIGet() {
        checkEndpointMeWithApplicationKey(applicationKey, applicationSecret: applicationSecret, consumerKey: consumerKey, expectationDescription: "Call API '/me'")
    }
    
    func testCallAPIGetWithURLParameters() {
        checkCredentials()
        
        let expectation = self.expectation(description: "Call API GET with URL parameters.")
        
        let APIWrapper = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: applicationKey, applicationSecret: applicationSecret, consumerKey: consumerKey)
        
        APIWrapper.get("/me/api/credential?status=validated") { result, error, request, response in
            XCTAssertTrue(Thread.isMainThread, "\(expectation) must run completion in the main thread.")
            XCTAssertNil(error, "\(expectation) must not return an error.")
            XCTAssertTrue(result is NSArray, "\(expectation) must return a NSArray object.")
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: timeout, handler: nil)
    }
    
    
    // MARK: - Annex methods
    
    fileprivate func checkCredentials() {
        XCTAssertFalse(applicationKey.characters.count == 0, "The application key must be defined.")
        XCTAssertFalse(applicationSecret.characters.count == 0, "The application secret must be defined.")
        XCTAssertFalse(consumerKey.characters.count == 0, "The consumer key must be defined.")
    }
    
    fileprivate func checkEndpointMeWithApplicationKey(_ applicationKey: String, applicationSecret: String, consumerKey: String?, expectationDescription: String) {
        checkCredentials()
        
        let expectation = self.expectation(description: expectationDescription)
        
        let APIWrapper = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: applicationKey, applicationSecret: applicationSecret, consumerKey: consumerKey)
        
        APIWrapper.get("/me") { result, error, request, response in
            XCTAssertTrue(Thread.isMainThread, "\(expectation) must run completion in the main thread.")
            
            // Wrong parameter cases.
            guard applicationKey != self.invalidValue && applicationSecret != self.invalidValue && consumerKey != self.invalidValue else {
                
                if let error = error as? OVHAPIError {
                    switch error {
                    case .requestError(let code, let httpCode, let errorCode, let message):
                        var expectedCode: Int = 0
                        var expectedHttpCode: String = ""
                        var expectedErrorCode: String = ""
                        var expectedMessage: String = ""
                        
                        if applicationKey == "x" {
                            expectedCode = 403
                            expectedHttpCode = "403 Forbidden"
                            expectedErrorCode = "INVALID_KEY"
                            expectedMessage = "This application key is invalid"
                        } else if applicationSecret == "x" {
                            expectedCode = 400
                            expectedHttpCode = "400 Bad Request"
                            expectedErrorCode = "INVALID_SIGNATURE"
                            expectedMessage = "Invalid signature"
                        } else if consumerKey == "x" {
                            expectedCode = 403
                            expectedHttpCode = "403 Forbidden"
                            expectedErrorCode = "NOT_CREDENTIAL"
                            expectedMessage = "This credential does not exist"
                        }
                        
                        XCTAssertEqual(code, expectedCode, "\(expectation) must return a '\(expectedCode)' as error.code.")
                        XCTAssertEqual(httpCode, expectedHttpCode, "\(expectation) must return a '\(expectedHttpCode)' as error.httpCode.")
                        XCTAssertEqual(errorCode, expectedErrorCode, "\(expectation) must return a '\(expectedErrorCode)' as error.errorCode.")
                        XCTAssertEqual(message, expectedMessage, "\(expectation) must return a '\(expectedMessage)' as error.message.")
                        
                    default: XCTFail("\(expectation) must return a 'OVHAPIError.RequestError' ad error.")
                    }
                } else {
                    XCTAssertTrue(error is OVHAPIError, "\(expectation) must return a 'OVHAPIError' as error.")
                }
                
                expectation.fulfill()
                return
            }
            
            // Check the error.
            guard error == nil else {
                if let error = error {
                    switch error {
                    case OVHAPIError.missingApplicationKey:
                        if applicationKey.characters.count > 0 {
                            XCTFail("\(expectation) must not return error OVHAPIError.MissingApplicationKey.")
                        }
                    case OVHAPIError.missingApplicationSecret:
                        if applicationSecret.characters.count > 0 {
                            XCTFail("\(expectation) must not return error OVHAPIError.MissingApplicationKey.")
                        }
                    case OVHAPIError.missingConsumerKey:
                        if consumerKey != nil && consumerKey!.characters.count > 0 {
                            XCTFail("\(expectation) must not throw error OVHAPIError.MissingConsumerKey.")
                        }
                        
                    default: XCTFail("\(expectation) must not return error \(error).")
                    }
                }
                
                expectation.fulfill()
                return
            }
            
            // Check the content.
            XCTAssertNil(error, "\(expectation) must not return an error.")
            XCTAssertTrue(result is NSDictionary, "\(expectation) must return a NSDictionary object.")
            
            if result is NSDictionary {
                let email = (result as! NSDictionary)["email"]
                XCTAssertNotNil(email, "\(expectation) result must contain a value for the key 'email'.")
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: timeout, handler: nil)
    }
    
}
