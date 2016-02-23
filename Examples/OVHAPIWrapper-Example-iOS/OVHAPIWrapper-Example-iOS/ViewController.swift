//
//  ViewController.swift
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

import UIKit
import OVHAPIWrapper

class ViewController: UITableViewController {
    
    // MARK: - Properties
    
    private var OVHAPI: OVHAPIWrapper?
    private var data: NSMutableArray = NSMutableArray()
    private var numberOfRequestsLaunched = 0
    
    private let sectionIndexDomains = 0
    private let sectionIndexHostingWebs = 1
    private let sectionIndexEmails = 2
    private let sectionIndexDedicatedServers = 3
    private let sectionIndexVPS = 4
    
    
    // MARK: - Methods
    
    private func loadDomainsWithCompletion(completion: () -> Void) {
        loadProductsWithPath("/domain", dataIndex: sectionIndexDomains, completion: completion)
    }
    
    private func loadHostingWebsWithCompletion(completion: () -> Void) {
        loadProductsWithPath("/hosting/web", dataIndex: sectionIndexHostingWebs, completion: completion)
    }
    
    private func loadEmailsWithCompletion(completion: () -> Void) {
        loadProductsWithPath("/email/domain", dataIndex: sectionIndexEmails, completion: completion)
    }
    
    private func loadDedicatedServersWithCompletion(completion: () -> Void) {
        loadProductsWithPath("/dedicated/server", dataIndex: sectionIndexDedicatedServers, completion: completion)
    }
    
    private func loadVPSWithCompletion(completion: () -> Void) {
        loadProductsWithPath("/vps", dataIndex: sectionIndexVPS, completion: completion)
    }
    
    private func loadProductsWithPath(path: String, dataIndex: Int, completion: () -> Void) {
        numberOfRequestsLaunched++
        
        OVHAPI?.get(path){ (result, error, request, response) -> Void in
            self.presentError(error)
            
            if result is NSArray {
                self.data[dataIndex] = (result as? NSArray)!
            }
            
            completion()
        }
    }
    
    private func presentError(error: ErrorType?) {
        guard error != nil else {
            return
        }
        
        var title: String? = error.debugDescription
        var message: String? = nil
        
        if let error = error as? OVHAPIError {
            title = error.description
            switch error {
            case OVHAPIError.MissingApplicationKey: message = "Please fix the Credentials.plist file."
            case OVHAPIError.MissingApplicationSecret: message = "Please fix the Credentials.plist file."
            case OVHAPIError.MissingConsumerKey: message = "Please authenticate first."
            case OVHAPIError.HttpError(let code): message = "code \(code)"
            case OVHAPIError.RequestError(_, let httpCode?, let errorCode?, _): message = "Error \(httpCode): \(errorCode)"
            default: break
            }
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .Alert)
        let action = UIAlertAction(title: "Close", style: .Cancel) { action in
            self.dismissViewControllerAnimated(true, completion: nil)
        }
        alert.addAction(action)
        
        presentViewController(alert, animated: true, completion: nil)
    }
    
    private func resetData() {
        data = NSMutableArray(arrayLiteral: NSArray(),NSArray(),NSArray(),NSArray(),NSArray())
    }
    
    
    // MARK: - Actions
    
    @IBAction func refreshProducts(sender: UIRefreshControl) {
        numberOfRequestsLaunched = 0
        
        let completion = { () -> Void in
            self.tableView.reloadData()
            
            self.numberOfRequestsLaunched--
            if self.numberOfRequestsLaunched <= 0 {
                sender.endRefreshing()
            }
        }
        
        loadDomainsWithCompletion(completion)
        loadHostingWebsWithCompletion(completion)
        loadEmailsWithCompletion(completion)
        loadDedicatedServersWithCompletion(completion)
        loadVPSWithCompletion(completion)
    }
    
    @IBAction func authenticate(sender: UIBarButtonItem) {
        sender.enabled = false
        
        OVHAPI?.requestCredentialsWithAccessRules(OVHAPIAccessRule.readOnlyRights(), redirectionUrl: "https://www.ovh.com/fr/") { (viewController, error) -> Void in
            guard error == nil else {
                self.presentError(error)
                sender.enabled = true
                return
            }
            
            if let viewController = viewController {
                viewController.completion = { consumerKeyIsValidated in
                    sender.enabled = true
                    
                    if consumerKeyIsValidated {
                        self.resetData()
                        self.tableView.reloadData()
                        
                        self.refreshControl?.beginRefreshing()
                        self.tableView.contentOffset = CGPointMake(0, -self.refreshControl!.frame.size.height);
                        self.refreshProducts(self.refreshControl!)
                    }
                }
                
                self.presentViewController(viewController, animated: true, completion: nil)
            }
        }
    }
    
    
    // MARK: - Table View delegate methods
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        if let _ = OVHAPI?.consumerKey {
            return data.count
        }
        
        return 1
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let _ = OVHAPI?.consumerKey {
            var numberOfRows: Int? = 0
            
            switch section {
            case sectionIndexDomains: numberOfRows = data[sectionIndexDomains].count
            case sectionIndexHostingWebs: numberOfRows = data[sectionIndexHostingWebs].count
            case sectionIndexEmails: numberOfRows = data[sectionIndexEmails].count
            case sectionIndexDedicatedServers: numberOfRows = data[sectionIndexDedicatedServers].count
            case sectionIndexVPS: numberOfRows = data[sectionIndexVPS].count
            default: numberOfRows = 0
            }
            
            if let numberOfRows = numberOfRows {
                return numberOfRows
            }
        }
        
        return 0
    }
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if let _ = OVHAPI?.consumerKey {
            var title: String?
            
            switch section {
            case sectionIndexDomains: title = "Domain"
            case sectionIndexHostingWebs: title = "Hosting Web"
            case sectionIndexEmails: title = "Email"
            case sectionIndexDedicatedServers: title = "Dedicated Server"
            case sectionIndexVPS: title = "VPS"
            default: title = nil
            }
            
            return title
        }
        
        return "Please authenticate first"
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("productCell")
        
        var source: NSArray?
        
        switch indexPath.section {
        case sectionIndexDomains: source = data[sectionIndexDomains] as? NSArray
        case sectionIndexHostingWebs: source = data[sectionIndexHostingWebs] as? NSArray
        case sectionIndexEmails: source = data[sectionIndexEmails] as? NSArray
        case sectionIndexDedicatedServers: source = data[sectionIndexDedicatedServers] as? NSArray
        case sectionIndexVPS: source = data[sectionIndexVPS] as? NSArray
        default: source = nil
        }
        
        cell!.textLabel?.text = source?.objectAtIndex(indexPath.row) as? String
        
        return cell!
    }
    
    
    // MARK: - View lifecycle
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        if let credentials = NSDictionary(contentsOfFile: NSBundle.mainBundle().pathForResource("Credentials", ofType: "plist")!) {
            OVHAPI = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: credentials["ApplicationKey"] as! String, applicationSecret: credentials["ApplicationSecret"] as! String, consumerKey: credentials["ConsumerKey"] as? String)
            OVHAPI?.enableLogs = true
        }
        
        resetData()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

