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
    private var deltaTime: NSTimeInterval? = nil
    
    // The request manager.
    private var requestManager: Alamofire.Manager
    static private var requestManagerCount = 0
    
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
    public init(endpoint: OVHAPIEndpoint, endpointVersion: String, applicationKey: String, applicationSecret: String, consumerKey: String? = nil, timeout: NSTimeInterval? = nil) {
        self.endpoint = "\(endpoint.rawValue)\(endpointVersion)"
        self.applicationKey = applicationKey
        self.applicationSecret = applicationSecret
        self.consumerKey = consumerKey
        
        var requestTimeout: NSTimeInterval = 30;
        if let timeout = timeout {
            requestTimeout = timeout
        }
        
        let configuration = NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier("com.ovh.apiwrapper.background\(OVHAPIWrapper.requestManagerCount++)")
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        requestManager = Alamofire.Manager(configuration: configuration)
        
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
    public convenience init(endpoint: OVHAPIEndpoint, applicationKey: String, applicationSecret: String, consumerKey: String? = nil, timeout: NSTimeInterval? = nil) {
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
    public func requestCredentialsWithAccessRules(accessRules: [OVHAPIAccessRule], redirectionUrl: String, completion: ((consumerKey: String?, validationUrl: String?, error: ErrorType?, request: NSURLRequest?, response: NSHTTPURLResponse?) -> Void)? = nil) {
        log("requesting credentials...")
        
        // Set the access rules to a dictionary of strings.
        var rules = [[String:String]]()
        for accessRule in accessRules {
            rules.append(accessRule.dictionaryRepresentation())
        }
        
        // Execute the request.
        rawCallWithMethod(.POST, path: "/auth/credential", content: ["accessRules": rules, "redirection": redirectionUrl], isAuthenticated: false, completion: { result, error, request, response in
            // Handle the request error.
            guard error == nil else {
                self.log("error while requesting credentials: \(error.debugDescription)")
                
                if let block = completion {
                    block(consumerKey: nil, validationUrl: nil, error: error, request: request, response: response)
                }
                return
            }
            
            // Request must return a dictionary object.
            guard result is NSDictionary else {
                self.log("get invalid response while requesting credentials")
                
                if let block = completion {
                    block(consumerKey: nil, validationUrl: nil, error: OVHAPIError.InvalidRequestResponse, request: request, response: response)
                }
                return
            }
            
            // The consumer key and the validation url are returned.
            let dictionary = result as! NSDictionary
            let consumerKey = dictionary["consumerKey"] as? String
            let validationUrl = dictionary["validationUrl"] as? String
            
            self.log("request credentials done, get consumer key: '\(consumerKey)' and validation url: '\(validationUrl)")
            
            self.consumerKey = consumerKey
            if let block = completion {
                block(consumerKey: consumerKey, validationUrl: validationUrl, error: error, request: request, response: response)
            }
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
    public func requestCredentialsWithAccessRules(accessRules: [OVHAPIAccessRule], redirectionUrl: String, completion: (viewController: OVHAPICredentialsViewController?, error: ErrorType?) -> Void) {
        let currentConsumerKey = consumerKey
        
        // Request the credentials.
        requestCredentialsWithAccessRules(accessRules, redirectionUrl: redirectionUrl) { (consumerKey, validationUrl, error, request, response) -> Void in
            // Handle the request error.
            guard error == nil else {
                completion(viewController: nil, error: error)
                return
            }
            
            // The request must return a validation url.
            guard validationUrl != nil else {
                completion(viewController: nil, error: OVHAPIError.InvalidRequestResponse)
                return
            }
            
            // Create the view controller to present to the user.
            let credentialsViewController = NSBundle(forClass: OVHAPICredentialsViewController.self).loadNibNamed("OVHAPICredentialsViewController", owner: nil, options: nil)[0] as! OVHAPICredentialsViewController
            credentialsViewController.validationUrl = validationUrl!
            credentialsViewController.redirectionUrl = redirectionUrl
            
            // If the authentication is canceled by the user, the consumer key is reset.
            credentialsViewController.cancelCompletion = {
                self.consumerKey = currentConsumerKey
            }
            
            completion(viewController: credentialsViewController, error: nil);
        }
    }
    #endif
    
    /**
    Wraps call to Ovh APIs for GET requests.
    
    - parameter path:       relative path of API request.
    - parameter completion: block called when the request is done.
    */
    public func get(path: String, completion: ((result: Any?, error: ErrorType?, request: NSURLRequest?, response: NSHTTPURLResponse?) -> Void)? = nil) {
        rawCallWithMethod(.GET, path: path, content: nil, isAuthenticated: true, completion: completion)
    }
    
    /**
    Wraps call to Ovh APIs for POST requests.
    
    - parameter path:       relative path of API request.
    - parameter content:    body of the request.
    - parameter completion: block called when the request is done.
    */
    public func post(path: String, content: [String : AnyObject]? = nil, completion: ((result: Any?, error: ErrorType?, request: NSURLRequest?, response: NSHTTPURLResponse?) -> Void)? = nil) {
        rawCallWithMethod(.POST, path: path, content: content, isAuthenticated: true, completion: completion)
    }
    
    /**
    Wraps call to Ovh APIs for PUT requests.
    
    - parameter path:       relative path of API request.
    - parameter content:    body of the request.
    - parameter completion: block called when the request is done.
    */
    public func put(path: String, content: [String : AnyObject]? = nil, completion: ((result: Any?, error: ErrorType?, request: NSURLRequest?, response: NSHTTPURLResponse?) -> Void)? = nil) {
        rawCallWithMethod(.PUT, path: path, content: content, isAuthenticated: true, completion: completion)
    }
    
    /**
    Wraps call to Ovh APIs for DELETE requests.
    
    - parameter path:       relative path of API request.
    - parameter completion: block called when the request is done.
    */
    public func delete(path: String, completion: ((result: Any?, error: ErrorType?, request: NSURLRequest?, response: NSHTTPURLResponse?) -> Void)? = nil) {
        rawCallWithMethod(.DELETE, path: path, content: nil, isAuthenticated: true, completion: completion)
    }
    
    
    // MARK: - Private methods
    
    /**
    Calculates the delta between local timestamp and API server timestamp.
    
    - parameter completion: block called when the request is done.
    */
    private func calculateDeltaTime(completion: ((ErrorType?) -> Void)?) {
        log("calculating delta time...")
        
        // Execute the request.
        requestManager.request(.GET, "\(endpoint)/auth/time")
            .responseString{ response in
                var error: ErrorType? = response.result.error
                
                if response.result.isSuccess {
                    if let value = response.result.value {
                        if let serverTimestamp = NSTimeInterval(value) {
                            self.deltaTime = serverTimestamp - NSDate().timeIntervalSince1970
                            self.log("calculate delta time done, get '\(self.deltaTime!)'")
                        }
                    }
                    
                    if self.deltaTime == nil {
                        error = OVHAPIError.InvalidRequestResponse
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
    private func log(log: String) {
        if enableLogs {
            NSLog("[OVH API] \(log)")
        }
    }
    
    /**
    This is the main func of this wrapper. It will sign a given query and return its result.
    
    - parameter method:             HTTP method of the request (GET, POST, DELETE, PUT, etc.).
    - parameter path:               relative path of API request.
    - parameter content:            body of the request.
    - parameter isAuthenticated:    true if the request uses authentication.
    - parameter completion:         block called when the request is done.
    */
    private func rawCallWithMethod(method: Alamofire.Method, path: String, content: [String : AnyObject]?, isAuthenticated: Bool = true, completion: ((Any?, ErrorType?, NSURLRequest?, NSHTTPURLResponse?) -> Void)? = nil) {
        // Define a closure to call the request.
        let rawCall = { () -> Void in
            let logPrefix = "[\(method.rawValue) \(path)]"
            
            var error: ErrorType? = nil
            
            // The application key and secret must be initialized before any request.
            if self.applicationKey.characters.count == 0 {
                self.log("\(logPrefix) the application key is missing")
                error = OVHAPIError.MissingApplicationKey
            }
            
            else if self.applicationSecret.characters.count == 0 {
                self.log("\(logPrefix) the application secret is missing")
                error = OVHAPIError.MissingApplicationSecret
            }
            
            // The consumer key property must be initialized before calling any authenticated request.
            else if isAuthenticated && (self.consumerKey == nil || self.consumerKey?.characters.count == 0) {
                self.log("\(logPrefix) the consuer key is missing")
                error = OVHAPIError.MissingConsumerKey
            }
            
            guard error == nil else {
                if let block = completion {
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
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
                let now = Int32(NSDate().timeIntervalSince1970 + self.deltaTime!)
                headers["X-Ovh-Timestamp"] = "\(now)"
                
                // Set the signature header.
                var jsonBody = ""
                if (method == .POST || method == .PUT) && content != nil {
                    do {
                        let data = try NSJSONSerialization.dataWithJSONObject(content!, options: [])
                        jsonBody = String(data: data, encoding: NSUTF8StringEncoding)!
                    } catch let error {
                        self.log("\(logPrefix) error while serializing JSON: \(error)")
                        
                        if let block = completion {
                            dispatch_async(dispatch_get_main_queue(), { () -> Void in
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
            self.requestManager.request(method, urlString, parameters: content, encoding: .JSON, headers: headers)
                .responseData { response in
                    // Log the response.
                    if let response = response.response {
                        self.log("\(logPrefix) done, response: \(response.statusCode)")
                    }
                    if let data = response.data {
                        self.log("\(logPrefix) done, data: \(String(data:data, encoding: NSUTF8StringEncoding)!)")
                    }
                    
                    guard completion != nil else {
                        return
                    }
                    
                    // Get the error of the request.
                    var error: ErrorType? = response.result.error
                    var httpReponseCode = 0
                    
                    if let statusCode = response.response?.statusCode {
                        httpReponseCode = statusCode
                        if  statusCode >= 400 {
                            error = OVHAPIError.HttpError(code: statusCode)
                        }
                    }
                    
                    // Get the content of the request.
                    var result: AnyObject?
                    
                    if let data = response.result.value {
                        do {
                            try result = NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.AllowFragments)
                            
                            if result is NSDictionary {
                                let dictionary = result as! NSDictionary
                                if let errorCode = dictionary["errorCode"] as? String {
                                    if let httpCode = dictionary["httpCode"] as? String {
                                        if let message = dictionary["message"] as? String {
                                            error = OVHAPIError.RequestError(code: httpReponseCode, httpCode: httpCode, errorCode: errorCode, message: message)
                                        }
                                    }
                                }
                            }
                        } catch {
                            result = String(data: data, encoding: NSUTF8StringEncoding)
                        }
                    }
                    
                    // Callback.
                    if let block = completion {
                        block(result, error, response.request, response.response)
                    }
            }
        }
        
        // If delta time is not defined, a request to calculate this delta time is launched first.
        guard deltaTime != nil else {
            calculateDeltaTime() { error in
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
