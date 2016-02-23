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
    
    private struct Product {
        let type: String
        let name: String
        
        func compareType(anotherProduct: Product) -> NSComparisonResult {
            return type.compare(anotherProduct.type)
        }
        
        func compareName(anotherProduct: Product) -> NSComparisonResult {
            return name.compare(anotherProduct.name)
        }
    }
    
    
    // MARK: - Properties
    
    private var OVHAPI: OVHAPIWrapper?
    private var data = [Product]()
    private var numberOfRequestsLaunched = 0
    private var numberOfRequestsDone = 0
    
    
    // MARK: - UI items
    
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    
    
    // MARK: - Methods
    
    private func loadDomainsWithCompletion(completion: () -> Void) {
        loadProductsWithPath("/domain", type: "domain", completion: completion)
    }
    
    private func loadHostingWebsWithCompletion(completion: () -> Void) {
        loadProductsWithPath("/hosting/web", type: "web hosting", completion: completion)
    }
    
    private func loadEmailsWithCompletion(completion: () -> Void) {
        loadProductsWithPath("/email/domain", type: "email", completion: completion)
    }
    
    private func loadDedicatedServersWithCompletion(completion: () -> Void) {
        loadProductsWithPath("/dedicated/server", type: "dedicated", completion: completion)
    }
    
    private func loadVPSWithCompletion(completion: () -> Void) {
        loadProductsWithPath("/vps", type: "vps", completion: completion)
    }
    
    private func loadProductsWithPath(path: String, type: String, completion: () -> Void) {
        numberOfRequestsLaunched++
        progressIndicator.maxValue++
        
        OVHAPI?.get(path){ (result, error, request, response) -> Void in
            self.presentError(error)
            
            if let result = (result as? [String]) {
                for name in result {
                    self.data.append(Product(type: type, name: name))
                    self.tableView.reloadData()
                }
            }
            
            self.numberOfRequestsDone++
            self.progressIndicator.doubleValue = Double(self.numberOfRequestsDone)
            
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
        
        let alert = NSAlert()
        alert.alertStyle = .WarningAlertStyle
        if let title = title {
            alert.messageText = title
        }
        if let message = message {
            alert.informativeText = message
        }
        alert.addButtonWithTitle("Close")
        alert.beginSheetModalForWindow(view.window!, completionHandler: nil)
    }
    
    private func resetData() {
        data.removeAll()
    }
    
    
    // MARK: - Actions
    
    @IBAction func refreshProducts(sender: NSButton) {
        numberOfRequestsLaunched = 0
        numberOfRequestsDone = 0
        progressIndicator.maxValue = 0
        progressIndicator.doubleValue = 0
        
        sender.enabled = false
        progressIndicator.hidden = false
        
        let completion = { () -> Void in
            if self.numberOfRequestsDone >= self.numberOfRequestsLaunched {
                // It is important to let the user see that the task is complete, so the 100% UI feedback is visible during a few seconds.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(1.0 * Double(NSEC_PER_SEC))), dispatch_get_main_queue(), { () -> Void in
                    sender.enabled = true
                    self.progressIndicator.hidden = true
                })
            }
        }
        
        loadDomainsWithCompletion(completion)
        loadHostingWebsWithCompletion(completion)
        loadEmailsWithCompletion(completion)
        loadDedicatedServersWithCompletion(completion)
        loadVPSWithCompletion(completion)
    }
    
    @IBAction func authenticate(sender: NSButton) {
        sender.enabled = false
        
        OVHAPI?.requestCredentialsWithAccessRules(OVHAPIAccessRule.readOnlyRights(), redirectionUrl: "https://www.ovh.com/fr/") { (consumerKey, validationUrl, error, request, response) -> Void in
            sender.enabled = true
            
            guard error == nil else {
                self.presentError(error)
                return
            }
            
            if let validationUrl = validationUrl {
                if let url = NSURL(string: validationUrl) {
                    NSWorkspace.sharedWorkspace().openURL(url)
                }
            }
        }
    }
    
    
    // MARK: - Table view data source
    
    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        return data.count
    }
    
    func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let result = tableView.makeViewWithIdentifier("productCell", owner: self)
        
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
    
    func tableView(tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if let sortDescriptor = tableView.sortDescriptors.first {
            if let key = sortDescriptor.key {
                var comparisonResult = NSComparisonResult.OrderedAscending
                if !sortDescriptor.ascending {
                    comparisonResult = .OrderedDescending
                }
                
                data.sortInPlace { (product1, product2) -> Bool in
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
        
        if let credentials = NSDictionary(contentsOfFile: NSBundle.mainBundle().pathForResource("Credentials", ofType: "plist")!) {
            OVHAPI = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: credentials["ApplicationKey"] as! String, applicationSecret: credentials["ApplicationSecret"] as! String, consumerKey: credentials["ConsumerKey"] as? String)
            OVHAPI?.enableLogs = true
        }
        
        resetData()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    override var representedObject: AnyObject? {
        didSet {
        // Update the view, if already loaded.
        }
    }


}

