//
//  OVHAPIWrapper.swift
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

import Foundation
import Alamofire
import CryptoSwift

/**
This wrapper helps to call the OVH APIs.
*/
final public class OVHAPIWrapper {
    
    // MARK: - Properties
    
    // Endpoint to selected API.
    public let endpoint: String
    
    // Key of the user application.
    public let applicationKey: String
    
    // Secret of the user application.
    public let applicationSecret: String
    
    // Consumer key of the user application.
    public var consumerKey: String? = nil
    
    // Delta between local timestamp and API server timestamp.
    fileprivate var deltaTime: TimeInterval? = nil
    
    // The request manager.
    fileprivate var requestManager: Alamofire.SessionManager
    static fileprivate var requestManagerCount = 0
    
    // Set to true if the logs must be enabled.
    public var enableLogs = false
    
    
    // MARK: - Lifecycle
    
    /**
    Initializes the `OVHAPIWrapper` instance with the specified application key,
    application secret, consumer key and endpoint.
    
    - parameter endpoint:           The endpoint to selected API.
    - parameter endpointVersion:    The version of the endpoint to selected API.
    - parameter applicationKey:     The key of the user application.
    - parameter applicationSecret:  The secret of the user application.
    - parameter consumerKey:        The consumer key of the user application.
    - parameter timeout:            The maximum amount of time that a request should be allowed to take.
    
    - returns: The new `OVHAPIWrapper` instance.
    */
    public init(endpoint: OVHAPIEndpoint, endpointVersion: String, applicationKey: String, applicationSecret: String, consumerKey: String? = nil, timeout: TimeInterval? = nil) {
        self.endpoint = "\(endpoint.rawValue)\(endpointVersion)"
        self.applicationKey = applicationKey
        self.applicationSecret = applicationSecret
        self.consumerKey = consumerKey
        
        var requestTimeout: TimeInterval = 30;
        if let timeout = timeout {
            requestTimeout = timeout
        }
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        requestManager = Alamofire.SessionManager(configuration: configuration)
        
        OVHAPIWrapper.requestManagerCount += 1
        
        log("API initialized with endpoint \(self.endpoint)")
    }
    
    /**
    Initializes the `OVHAPIWrapper` instance with the specified application key,
    application secret, consumer key and endpoint.
    This is a convenience initializer to set automatically the latest version
    of the endpoint.
    
    - parameter endpoint:           The endpoint to selected API.
    - parameter applicationKey:     The key of the user application.
    - parameter applicationSecret:  The secret of the user application.
    - parameter consumerKey:        The consumer key of the user application.
    - parameter timeout:            The maximum amount of time that a request should be allowed to take.
    
    - returns: The new `OVHAPIWrapper` instance.
    */
    public convenience init(endpoint: OVHAPIEndpoint, applicationKey: String, applicationSecret: String, consumerKey: String? = nil, timeout: TimeInterval? = nil) {
        var endpointVersion: String
        switch endpoint {
        case .OVHEU:
            endpointVersion = OVHAPIEndPointVersion.latestOVHEU
        case .OVHCA:
            endpointVersion = OVHAPIEndPointVersion.latestOVHCA
        case .kimsufiEU:
            endpointVersion = OVHAPIEndPointVersion.latestKimsufiEU
        case .kimsufiCA:
            endpointVersion = OVHAPIEndPointVersion.latestKimsufiCA
        case .soYouStartEU:
            endpointVersion = OVHAPIEndPointVersion.latestSoYouStartEU
        case .soYouStartCA:
            endpointVersion = OVHAPIEndPointVersion.latestSoYouStartCA
        case .runabove:
            endpointVersion = OVHAPIEndPointVersion.latestRunabove
        }
        
        self.init(endpoint: endpoint, endpointVersion: endpointVersion, applicationKey: applicationKey, applicationSecret: applicationSecret, consumerKey: consumerKey, timeout: timeout)
    }
    
    
    // MARK: - Public methods
    
    /**
    Requests credentials from the API.
    Use this method to handle yourself the validation of the consumer key
    (i.e. display the page from the validation URL)
    
    - parameter accessRules:    list of rules your application need.
    - parameter redirectionUrl: url to redirect on your website after authentication.
    - parameter completion:     block called when the request is done.
    */
    public func requestCredentials(withAccessRules accessRules: [OVHAPIAccessRule], redirection redirectionUrl: String, andCompletion completion: ((_ consumerKey: String?, _ validationUrl: String?, _ error: Error?, _ request: URLRequest?, _ response: HTTPURLResponse?) -> Void)? = nil) {
        log("requesting credentials...")
        
        // Set the access rules to a dictionary of strings.
        var rules = [[String:String]]()
        for accessRule in accessRules {
            rules.append(accessRule.dictionaryRepresentation())
        }
        
        // Execute the request.
        rawCall(withMethod: .post, path: "/auth/credential", content: ["accessRules": rules as AnyObject, "redirection": redirectionUrl as AnyObject], authentication: false, andCompletion: { (result, error, request, response) in
            // Defer the handler.
            var consumerKey: String?
            var validationUrl: String?
            var completionError: Error?
            defer {
                if let block = completion {
                    block(consumerKey, validationUrl, completionError, request, response)
                }
            }
            
            // Handle the request error.
            guard error == nil else {
                self.log("error while requesting credentials: \(error.debugDescription)")
                completionError = error
                return
            }
            
            // Request must return a dictionary object.
            guard let dictionary = result as? NSDictionary else {
                self.log("get invalid response while requesting credentials")
                completionError = OVHAPIError.invalidRequestResponse
                return
            }
            
            // The consumer key and the validation url are returned.
            consumerKey = dictionary["consumerKey"] as? String
            validationUrl = dictionary["validationUrl"] as? String
            
            self.log("request credentials done, get consumer key: '\(consumerKey)' and validation url: '\(validationUrl)")
            
            self.consumerKey = consumerKey
        })
    }
    
    #if os(iOS)
    /**
     Requests credentials from the API.
     Use this method to get a viewcontroller to display in order to validate the consumer key.
     The completion handler gives you a viewcontroller, you are responsible to present it.
     
     - parameter accessRules:       list of rules your application need.
     - parameter redirectionUrl:    url to redirect on your website after authentication.
     - parameter completion:        block called when the request is done.
     */
    public func requestCredentials(withAccessRules accessRules: [OVHAPIAccessRule], redirection redirectionUrl: String, andCompletion completion: @escaping (_ viewController: OVHAPICredentialsViewController?, _ error: Error?) -> Void) {
        let currentConsumerKey = consumerKey
        
        // Request the credentials.
        requestCredentials(withAccessRules: accessRules, redirection: redirectionUrl) { (consumerKey, validationUrl, error, request, response) in
            // Defer the handler.
            var credentialsViewController: OVHAPICredentialsViewController?
            var completionError: Error?
            defer {
                completion(credentialsViewController, completionError);
            }
            
            // Handle the request error.
            guard error == nil else {
                completionError = error
                return
            }
            
            // The request must return a validation url.
            guard let url = validationUrl else {
                completionError = OVHAPIError.invalidRequestResponse
                return
            }
            
            // Create the view controller to present to the user.
            if let viewControllers = Bundle(for: OVHAPICredentialsViewController.self).loadNibNamed("OVHAPICredentialsViewController", owner: nil, options: nil), let viewController = viewControllers.first as? OVHAPICredentialsViewController {
                credentialsViewController = viewController
                credentialsViewController?.validationUrl = url
                credentialsViewController?.redirectionUrl = url
                
                // If the authentication is canceled by the user, the consumer key is reset.
                credentialsViewController?.cancelCompletion = {
                    self.consumerKey = currentConsumerKey
                }
            }
        }
    }
    #endif
    
    /**
    Wraps call to Ovh APIs for GET requests.
    
    - parameter path:       relative path of API request.
    - parameter completion: block called when the request is done.
    */
    public func get(_ path: String, completion: ((_ result: Any?, _ error: Error?, _ request: URLRequest?, _ response: HTTPURLResponse?) -> Void)? = nil) {
        rawCall(withMethod: .get, path: path, content: nil, authentication: true, andCompletion: completion)
    }
    
    /**
    Wraps call to Ovh APIs for POST requests.
    
    - parameter path:       relative path of API request.
    - parameter content:    body of the request.
    - parameter completion: block called when the request is done.
    */
    public func post(_ path: String, content: [String : AnyObject]? = nil, completion: ((_ result: Any?, _ error: Error?, _ request: URLRequest?, _ response: HTTPURLResponse?) -> Void)? = nil) {
        rawCall(withMethod: .post, path: path, content: content, authentication: true, andCompletion: completion)
    }
    
    /**
    Wraps call to Ovh APIs for PUT requests.
    
    - parameter path:       relative path of API request.
    - parameter content:    body of the request.
    - parameter completion: block called when the request is done.
    */
    public func put(_ path: String, content: [String : AnyObject]? = nil, completion: ((_ result: Any?, _ error: Error?, _ request: URLRequest?, _ response: HTTPURLResponse?) -> Void)? = nil) {
        rawCall(withMethod: .put, path: path, content: content, authentication: true, andCompletion: completion)
    }
    
    /**
    Wraps call to Ovh APIs for DELETE requests.
    
    - parameter path:       relative path of API request.
    - parameter completion: block called when the request is done.
    */
    public func delete(_ path: String, completion: ((_ result: Any?, _ error: Error?, _ request: URLRequest?, _ response: HTTPURLResponse?) -> Void)? = nil) {
        rawCall(withMethod: .delete, path: path, content: nil, authentication: true, andCompletion: completion)
    }
    
    
    // MARK: - Private methods
    
    /**
    Calculates the delta between local timestamp and API server timestamp.
    
    - parameter completion: block called when the request is done.
    */
    fileprivate func calculateDeltaTime(withCompletion completion: ((Error?) -> Void)? = nil) {
        log("calculating delta time...")
        
        // Execute the request.
        requestManager.request("\(endpoint)/auth/time")
            .responseString{ (response) in
                var error = response.result.error
                
                if response.result.isSuccess {
                    if let value = response.result.value, let serverTimestamp = TimeInterval(value) {
                        self.deltaTime = serverTimestamp - NSDate().timeIntervalSince1970
                        self.log("calculate delta time done, get '\(self.deltaTime!)'")
                    }
                    
                    if self.deltaTime == nil {
                        error = OVHAPIError.invalidRequestResponse
                    }
                }
                
                if error != nil {
                    self.log("error while calculating delta time: \(error.debugDescription)")
                }
                
                if let block = completion {
                    block(error)
                }
        }
    }
    
    /**
    Log to console.
     
    - parameter log: string to log in the console.
    */
    fileprivate func log(_ log: String) {
        if enableLogs {
            print("[OVH API] \(log)")
        }
    }
    
    /**
    This is the main func of this wrapper. It will sign a given query and return its result.
    
    - parameter method:             HTTP method of the request (get, post, delete, put, etc.).
    - parameter path:               relative path of API request.
    - parameter content:            body of the request.
    - parameter isAuthenticated:    true if the request uses authentication.
    - parameter completion:         block called when the request is done.
    */
    fileprivate func rawCall(withMethod method: HTTPMethod, path: String, content: [String : AnyObject]?, authentication isAuthenticated: Bool = true, andCompletion completion: ((Any?, Error?, URLRequest?, HTTPURLResponse?) -> Void)? = nil) {
        // Define a closure to call the request.
        let rawCall = {
            let logPrefix = "[\(method.rawValue) \(path)]"
            
            var error: Error? = nil
            
            // The application key and secret must be initialized before any request.
            if self.applicationKey.characters.count == 0 {
                self.log("\(logPrefix) the application key is missing")
                error = OVHAPIError.missingApplicationKey
            }
            
            else if self.applicationSecret.characters.count == 0 {
                self.log("\(logPrefix) the application secret is missing")
                error = OVHAPIError.missingApplicationSecret
            }
            
            // The consumer key property must be initialized before calling any authenticated request.
            else if isAuthenticated && (self.consumerKey == nil || self.consumerKey?.characters.count == 0) {
                self.log("\(logPrefix) the consuer key is missing")
                error = OVHAPIError.missingConsumerKey
            }
            
            guard error == nil else {
                if let block = completion {
                    DispatchQueue.main.async(execute: {
                        block(nil, error, nil, nil)
                    })
                }
                return
            }
            
            // Get the final endpoint.
            let urlString = "\(self.endpoint)\(path)"
            
            // Set the default headers.
            var headers = [String : String]()
            headers["Content-Type"] = "application/json; charset=utf-8"
            headers["X-Ovh-Application"] = self.applicationKey
            
            if isAuthenticated {
                // Set the timestamp header.
                let now = Int32(Date().timeIntervalSince1970 + self.deltaTime!)
                headers["X-Ovh-Timestamp"] = "\(now)"
                
                // Set the signature header.
                var jsonBody = ""
                if (method == .post || method == .put) && content != nil {
                    do {
                        let data = try JSONSerialization.data(withJSONObject: content!, options: [])
                        jsonBody = String(data: data, encoding: String.Encoding.utf8)!
                    } catch let error {
                        self.log("\(logPrefix) error while serializing JSON: \(error)")
                        
                        if let block = completion {
                            DispatchQueue.main.async(execute: {
                                block(nil, error, nil, nil)
                            })
                        }
                        return
                    }
                }
                
                let toSign = "\(self.applicationSecret)+\(self.consumerKey!)+\(method.rawValue)+\(urlString)+\(jsonBody)+\(now)"
                let signature = toSign.sha1()
                
                headers["X-Ovh-Signature"] = "$1$\(signature)"
                
                // Set the consumer header.
                headers["X-Ovh-Consumer"] = self.consumerKey!
            }
            
            self.log("\(logPrefix) headers: \(headers)")
            
            // Execute the request.
            self.requestManager.request(urlString, method: method, parameters: content, encoding: JSONEncoding.default, headers: headers)
                .responseJSON { (response) in
                    // Log the response.
                    if let response = response.response {
                        self.log("\(logPrefix) done, response: \(response.statusCode)")
                    }
                    if let data = response.data {
                        self.log("\(logPrefix) done, data: \(String(data:data, encoding: String.Encoding.utf8)!)")
                    }
                    
                    guard completion != nil else {
                        return
                    }
                    
                    // Get the error of the request.
                    var error = response.result.error
                    var httpReponseCode = 0
                    
                    if let statusCode = response.response?.statusCode {
                        httpReponseCode = statusCode
                        if  statusCode >= 400 {
                            error = OVHAPIError.httpError(code: statusCode)
                        }
                    }
                    
                    if let dictionary = response.result.value as? NSDictionary, let message = dictionary["message"] as? String {
                        error = OVHAPIError.requestError(code: httpReponseCode, httpCode: dictionary["httpCode"] as? String, errorCode: dictionary["errorCode"] as? String, message: message)
                    }
                    
                    // Callback.
                    if let block = completion {
                        block(response.result.value, error, response.request, response.response)
                    }
            }
        }
        
        // If delta time is not defined, a request to calculate this delta time is launched first.
        guard deltaTime != nil else {
            calculateDeltaTime() { (error) in
                // Handle the request error.
                guard error == nil else {
                    if let block = completion {
                        block(nil, error, nil, nil)
                    }
                    return
                }
                
                // Execute the "real" request.
                rawCall()
            }
            return
        }
        
        // Execute the request.
        rawCall()
    }
}
