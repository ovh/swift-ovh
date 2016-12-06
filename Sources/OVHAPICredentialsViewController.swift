//
//  OVHAPICredentialsViewController.swift
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
import UIKit

open class OVHAPICredentialsViewController: UINavigationController, UIWebViewDelegate {
    
    // MARK: - Properties
    
    // URL of the validation page to display.
    var validationUrl: String = ""
    
    // URL of the page to display once the consumer key is validated.
    var redirectionUrl: String = ""
    
    // Flag to know if the consumer key is validated by the user.
    fileprivate var consumerKeyValidated: Bool = false
    
    // The block called as soon as the credentials view controller is dismissed.
    // The Bool value is set to true if the consumer key is validated, false else.
    open var completion: ((Bool) -> ())?
    
    // Block called when the view controller is dismissed without validating the consumer key.
    var cancelCompletion: (() -> ())?
    
    // The webview in which the page will be displayed.
    @IBOutlet fileprivate weak var webView: UIWebView!
    
    
    // MARK: - Lifecycle
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        if let url = URL.init(string: validationUrl) {
            let request = URLRequest.init(url: url)
            webView.loadRequest(request)
        }
    }
    
    
    // MARK: - Actions
    
    @IBAction func dismiss(_ sender: AnyObject) {
        if !consumerKeyValidated {
            if let block = cancelCompletion {
                block()
            }
        }
        
        self.dismiss(animated: true) {
            if let block = self.completion {
                block(self.consumerKeyValidated)
            }
        }
    }
    
    
    // MARK: - WebView delegate methods
    
    open func webViewDidFinishLoad(_ webView: UIWebView) {
        if let url = webView.request?.url?.absoluteString {
            consumerKeyValidated = (url == redirectionUrl)
        }
    }
    
    open func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
        let alert = UIAlertController(title: error.localizedDescription, message: error.localizedDescription, preferredStyle: .alert)
        let action = UIAlertAction(title: "Close", style: .cancel){ (action) in
            self.dismiss(animated: true, completion: nil)
        }
        alert.addAction(action)
        
        present(alert, animated: true, completion: nil)
    }
}
