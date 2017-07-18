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
    
    fileprivate var OVHAPI: OVHAPIWrapper?
    fileprivate var data: NSMutableArray = NSMutableArray()
    fileprivate var numberOfRequestsLaunched = 0
    
    fileprivate let sectionIndexDomains = 0
    fileprivate let sectionIndexHostingWebs = 1
    fileprivate let sectionIndexEmails = 2
    fileprivate let sectionIndexDedicatedServers = 3
    fileprivate let sectionIndexVPS = 4
    
    
    // MARK: - Methods
    
    fileprivate func loadDomains(withCompletion completion: @escaping () -> Void) {
        loadProducts(withPath: "/domain", dataIndex: sectionIndexDomains, completion: completion)
    }
    
    fileprivate func loadHostingWebs(withCompletion completion: @escaping () -> Void) {
        loadProducts(withPath: "/hosting/web", dataIndex: sectionIndexHostingWebs, completion: completion)
    }
    
    fileprivate func loadEmails(withCompletion completion: @escaping () -> Void) {
        loadProducts(withPath: "/email/domain", dataIndex: sectionIndexEmails, completion: completion)
    }
    
    fileprivate func loadDedicatedServers(withCompletion completion: @escaping () -> Void) {
        loadProducts(withPath: "/dedicated/server", dataIndex: sectionIndexDedicatedServers, completion: completion)
    }
    
    fileprivate func loadVPS(withCompletion completion: @escaping () -> Void) {
        loadProducts(withPath: "/vps", dataIndex: sectionIndexVPS, completion: completion)
    }
    
    fileprivate func loadProducts(withPath path: String, dataIndex: Int, completion: @escaping () -> Void) {
        numberOfRequestsLaunched += 1
        
        OVHAPI?.get(path){ (result, error, request, response) -> Void in
            self.present(error)
            
            if result is NSArray {
                self.data[dataIndex] = (result as? NSArray)!
            }
            
            completion()
        }
    }
    
    fileprivate func present(_ error: Error?) {
        guard error != nil else {
            return
        }
        
        var title: String? = error.debugDescription
        var message: String? = nil
        
        if let error = error as? OVHAPIError {
            title = error.description
            switch error {
            case OVHAPIError.missingApplicationKey: message = "Please fix the Credentials.plist file."
            case OVHAPIError.missingApplicationSecret: message = "Please fix the Credentials.plist file."
            case OVHAPIError.missingConsumerKey: message = "Please authenticate first."
            case OVHAPIError.httpError(let code): message = "code \(code)"
            case OVHAPIError.requestError(_, let httpCode?, let errorCode?, _): message = "Error \(httpCode): \(errorCode)"
            default: break
            }
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let action = UIAlertAction(title: "Close", style: .cancel) { action in
            self.dismiss(animated: true, completion: nil)
        }
        alert.addAction(action)
        
        present(alert, animated: true, completion: nil)
    }
    
    fileprivate func resetData() {
        data = NSMutableArray(arrayLiteral: NSArray(),NSArray(),NSArray(),NSArray(),NSArray())
    }
    
    
    // MARK: - Actions
    
    @IBAction func refreshProducts(_ sender: UIRefreshControl) {
        numberOfRequestsLaunched = 0
        
        let completion = { () -> Void in
            self.tableView.reloadData()
            
            self.numberOfRequestsLaunched -= 1
            if self.numberOfRequestsLaunched <= 0 {
                sender.endRefreshing()
            }
        }
        
        loadDomains(withCompletion: completion)
        loadHostingWebs(withCompletion: completion)
        loadEmails(withCompletion: completion)
        loadDedicatedServers(withCompletion: completion)
        loadVPS(withCompletion: completion)
    }
    
    @IBAction func authenticate(_ sender: UIBarButtonItem) {
        sender.isEnabled = false
        
        OVHAPI?.requestCredentials(withAccessRules: OVHAPIAccessRule.readOnlyRights(), redirection: "https://www.ovh.com/fr/") { (viewController, error) -> Void in
            guard error == nil else {
                self.present(error)
                sender.isEnabled = true
                return
            }
            
            if let viewController = viewController {
                viewController.completion = { consumerKeyIsValidated in
                    sender.isEnabled = true
                    
                    if consumerKeyIsValidated {
                        self.resetData()
                        self.tableView.reloadData()
                        
                        self.refreshControl?.beginRefreshing()
                        self.tableView.contentOffset = CGPoint(x: 0, y: -self.refreshControl!.frame.size.height);
                        self.refreshProducts(self.refreshControl!)
                    }
                }
                
                self.present(viewController, animated: true, completion: nil)
            }
        }
    }
    
    
    // MARK: - Table View delegate methods
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        if let _ = OVHAPI?.consumerKey {
            return data.count
        }
        
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let _ = OVHAPI?.consumerKey {
            var numberOfRows: Int? = 0
            
            switch section {
            case sectionIndexDomains: numberOfRows = (data[sectionIndexDomains] as AnyObject).count
            case sectionIndexHostingWebs: numberOfRows = (data[sectionIndexHostingWebs] as AnyObject).count
            case sectionIndexEmails: numberOfRows = (data[sectionIndexEmails] as AnyObject).count
            case sectionIndexDedicatedServers: numberOfRows = (data[sectionIndexDedicatedServers] as AnyObject).count
            case sectionIndexVPS: numberOfRows = (data[sectionIndexVPS] as AnyObject).count
            default: numberOfRows = 0
            }
            
            if let numberOfRows = numberOfRows {
                return numberOfRows
            }
        }
        
        return 0
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
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
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "productCell")
        
        var source: NSArray?
        
        switch indexPath.section {
        case sectionIndexDomains: source = data[sectionIndexDomains] as? NSArray
        case sectionIndexHostingWebs: source = data[sectionIndexHostingWebs] as? NSArray
        case sectionIndexEmails: source = data[sectionIndexEmails] as? NSArray
        case sectionIndexDedicatedServers: source = data[sectionIndexDedicatedServers] as? NSArray
        case sectionIndexVPS: source = data[sectionIndexVPS] as? NSArray
        default: source = nil
        }
        
        cell!.textLabel?.text = source?.object(at: indexPath.row) as? String
        
        return cell!
    }
    
    
    // MARK: - View lifecycle
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        if let credentials = NSDictionary(contentsOfFile: Bundle.main.path(forResource: "Credentials", ofType: "plist")!) {
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

