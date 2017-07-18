//
//  ViewController.swift
//  OVHAPIWrapper-Example-OSX
//
//  Created by Cyril on 04/02/2016.
//  Copyright © 2016 OVH SAS. All rights reserved.
//

import Cocoa
import OVHAPIWrapper

class ViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    
    // MARK: - Structs
    
    fileprivate struct Product {
        let type: String
        let name: String
        
        func compareType(_ anotherProduct: Product) -> ComparisonResult {
            return type.compare(anotherProduct.type)
        }
        
        func compareName(_ anotherProduct: Product) -> ComparisonResult {
            return name.compare(anotherProduct.name)
        }
    }
    
    
    // MARK: - Properties
    
    fileprivate var OVHAPI: OVHAPIWrapper?
    fileprivate var data = [Product]()
    fileprivate var numberOfRequestsLaunched = 0
    fileprivate var numberOfRequestsDone = 0
    
    
    // MARK: - UI items
    
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    
    
    // MARK: - Methods
    
    fileprivate func loadDomains(withCompletion completion: @escaping () -> Void) {
        loadProducts(withPath: "/domain", type: "domain", completion: completion)
    }
    
    fileprivate func loadHostingWebs(withCompletion completion: @escaping () -> Void) {
        loadProducts(withPath: "/hosting/web", type: "web hosting", completion: completion)
    }
    
    fileprivate func loadEmails(withCompletion completion: @escaping () -> Void) {
        loadProducts(withPath: "/email/domain", type: "email", completion: completion)
    }
    
    fileprivate func loadDedicatedServers(withCompletion completion: @escaping () -> Void) {
        loadProducts(withPath: "/dedicated/server", type: "dedicated", completion: completion)
    }
    
    fileprivate func loadVPS(withCompletion completion: @escaping () -> Void) {
        loadProducts(withPath: "/vps", type: "vps", completion: completion)
    }
    
    fileprivate func loadProducts(withPath path: String, type: String, completion: @escaping () -> Void) {
        numberOfRequestsLaunched += 1
        progressIndicator.maxValue += 1
        
        OVHAPI?.get(path){ (result, error, request, response) -> Void in
            self.present(error)
            
            if let result = (result as? [String]) {
                for name in result {
                    self.data.append(Product(type: type, name: name))
                    self.tableView.reloadData()
                }
            }
            
            self.numberOfRequestsDone += 1
            self.progressIndicator.doubleValue = Double(self.numberOfRequestsDone)
            
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
        
        let alert = NSAlert()
        alert.alertStyle = .warning
        if let title = title {
            alert.messageText = title
        }
        if let message = message {
            alert.informativeText = message
        }
        alert.addButton(withTitle: "Close")
        alert.beginSheetModal(for: view.window!, completionHandler: nil)
    }
    
    fileprivate func resetData() {
        data.removeAll()
    }
    
    
    // MARK: - Actions
    
    @IBAction func refreshProducts(_ sender: NSButton) {
        numberOfRequestsLaunched = 0
        numberOfRequestsDone = 0
        progressIndicator.maxValue = 0
        progressIndicator.doubleValue = 0
        
        sender.isEnabled = false
        progressIndicator.isHidden = false
        
        let completion = { () -> Void in
            if self.numberOfRequestsDone >= self.numberOfRequestsLaunched {
                // It is important to let the user see that the task is complete, so the 100% UI feedback is visible during a few seconds.
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(1.0 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: { () -> Void in
                    sender.isEnabled = true
                    self.progressIndicator.isHidden = true
                })
            }
        }
        
        loadDomains(withCompletion: completion)
        loadHostingWebs(withCompletion: completion)
        loadEmails(withCompletion: completion)
        loadDedicatedServers(withCompletion: completion)
        loadVPS(withCompletion: completion)
    }
    
    @IBAction func authenticate(_ sender: NSButton) {
        sender.isEnabled = false
        
        OVHAPI?.requestCredentials(withAccessRules: OVHAPIAccessRule.readOnlyRights(), redirection: "https://www.ovh.com/fr/") { (consumerKey, validationUrl, error, request, response) -> Void in
            sender.isEnabled = true
            
            guard error == nil else {
                self.present(error)
                return
            }
            
            if let validationUrl = validationUrl {
                if let url = NSURL(string: validationUrl) {
                    NSWorkspace.shared().open(url as URL)
                }
            }
        }
    }
    
    
    // MARK: - Table view data source
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return data.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let result = tableView.make(withIdentifier: "productCell", owner: self)
        
        if let result = (result as? NSTableCellView) {
            var value: String = ""
            
            if let identifier = tableColumn?.identifier {
                switch identifier {
                case "productType": value = data[row].type
                case "productName": value = data[row].name
                default: value = ""
                }
            }
            
            result.textField?.stringValue = value
        }
        
        return result
    }
    
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if let sortDescriptor = tableView.sortDescriptors.first {
            if let key = sortDescriptor.key {
                var comparisonResult = ComparisonResult.orderedAscending
                if !sortDescriptor.ascending {
                    comparisonResult = .orderedDescending
                }
                
                data.sort { (product1, product2) -> Bool in
                    switch key {
                    case "type": return product1.compareType(product2) == comparisonResult
                    case "name": return product1.compareName(product2) == comparisonResult
                    default: return true
                    }
                }
                
                tableView.reloadData()
            }
        }
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

        // Do any additional setup after loading the view.
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


}

