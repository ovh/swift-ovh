//
//  ProductsViewController.swift
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
import CoreData
import OVHAPIWrapper

class ProductsViewController: UICollectionViewController, NSFetchedResultsControllerDelegate {
    
    // MARK: - Properties
    
    lazy private var fetchedResultsController: NSFetchedResultsController = {
        let fetchRequest = NSFetchRequest(entityName: "OVHVPS")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "displayName", ascending: true)]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: CoreDataManager.sharedManager.managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        
        return fetchedResultsController
    }()
    
    typealias changes = () -> ()
    private var sectionsChanges = [changes]()
    private var objectChanges = [changes]()

    
    // MARK: - UI elements
    
    @IBOutlet weak var authenticateButton: UIBarButtonItem!
    private var refreshControl: UIRefreshControl?
    
    
    // MARK: - Actions
    
    @IBAction func authenticate(sender: UIBarButtonItem) {
        sender.enabled = false;
        
        OVHVPSController.sharedController.OVHAPI.requestCredentialsWithAccessRules([OVHAPIAccessRule(method: .GET, path: "/vps*"), OVHAPIAccessRule(method: .POST, path: "/vps*")], redirectionUrl: "https://www.ovh.com/fr/") { (viewController, error) -> Void in
            guard error == nil else {
                self.presentError(error)
                sender.enabled = true
                return
            }
            
            if let viewController = viewController {
                viewController.completion = { consumerKeyIsValidated in
                    sender.enabled = true
                    
                    if consumerKeyIsValidated {
                        self.refreshControl?.beginRefreshing()
                        self.collectionView?.contentOffset = CGPointMake(0, -self.refreshControl!.frame.size.height);
                        self.refreshVPS(self.refreshControl!)
                        
                        // Send to the watch the updated credentials.
                        WatchSessionManager.sharedManager.updateAPICredentials()
                    }
                }
                
                self.presentViewController(viewController, animated: true, completion: nil)
            }
        }
    }
    
    @IBAction func refreshVPS(sender: UIRefreshControl) {
        OVHVPSController.sharedController.loadVPSWithBlock({ error -> Void in
            self.presentError(error)
            self.refreshControl?.endRefreshing()
        })
    }
    
    
    // MARK: - UICollectionViewController delegate methods
    
    override func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        if let count = fetchedResultsController.sections?.count {
            return count
        }
        
        return 0
    }
    
    override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if let sectionInfo = fetchedResultsController.sections?[section] {
            return sectionInfo.numberOfObjects
        }
        
        return 0
    }
    
    override func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier("VPSCell", forIndexPath: indexPath)
        let VPS = fetchedResultsController.objectAtIndexPath(indexPath) as! OVHVPS
        
        configureCell(cell, withVPS: VPS)
        
        return cell
    }
    
    override func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        let VPS = fetchedResultsController.objectAtIndexPath(indexPath) as! OVHVPS
        
        // No action on the busy VPS.
        guard !VPS.isBusy() && !VPS.isStateUnknown() else {
            return
        }
        
        let VPSName = VPS.name!
        
        // Create the alert controller to present to the user.
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
        
        // Add the 'start' action.
        if VPS.isStopped() {
            let startAction = UIAlertAction(title: "Start", style: .Default, handler: { action -> Void in
                OVHVPSController.sharedController.startVPSWithName(VPSName, completionBlock: { (task, error) -> Void in
                    self.presentError(error)
                })
            })
            alertController.addAction(startAction)
        }
        
        if VPS.isRunning() {
            // Add the 'reboot' action.
            let rebootAction = UIAlertAction(title: "Reboot", style: .Default, handler: { action -> Void in
                OVHVPSController.sharedController.rebootVPSWithName(VPSName, completionBlock: { (task, error) -> Void in
                    self.presentError(error)
                })
            })
            alertController.addAction(rebootAction)
            
            // Add the 'stop' action.
            let stopAction = UIAlertAction(title: "Stop", style: .Destructive, handler: { action -> Void in
                OVHVPSController.sharedController.stopVPSWithName(VPSName, completionBlock: { (task, error) -> Void in
                    self.presentError(error)
                })
            })
            alertController.addAction(stopAction)
        }
        
        // Add the 'cancel' action.
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: { action -> Void in
            alertController.dismissViewControllerAnimated(true, completion: nil)
        })
        alertController.addAction(cancelAction)
        
        // A popover is created on the devices supporting this feature (iPad).
        if let popoverPresentationController = alertController.popoverPresentationController {
            alertController.modalPresentationStyle = .Popover
            
            if let cell = collectionView.cellForItemAtIndexPath(indexPath) {
                popoverPresentationController.sourceView = cell
                popoverPresentationController.sourceRect = cell.bounds
            }
        }
        
        // Present the alert controller to the user.
        presentViewController(alertController, animated: true, completion: nil)
    }
    
    
    // MARK: - FetchedController delegate methods
    
    func controllerWillChangeContent(controller: NSFetchedResultsController) {
        sectionsChanges.removeAll()
        objectChanges.removeAll()
    }
    
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        collectionView?.performBatchUpdates({ () -> Void in
            for block in self.sectionsChanges {
                block()
            }
            
            for block in self.objectChanges {
                block()
            }
            
            }, completion: { (Bool) -> Void in
                self.sectionsChanges.removeAll()
                self.objectChanges.removeAll()
        })
    }
    
    func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        let sections = NSIndexSet(index: sectionIndex)
        
        switch (type) {
        case .Insert:
            sectionsChanges.append({ () -> () in
                self.collectionView?.insertSections(sections)
            })
        case .Delete:
            sectionsChanges.append({ () -> () in
                self.collectionView?.deleteSections(sections)
            })
        case .Update:
            sectionsChanges.append({ () -> () in
                self.collectionView?.reloadSections(sections)
            })
        case .Move:
            break
        }
    }
    
    func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        switch (type) {
        case .Insert:
            if let newIndexPath = newIndexPath {
                objectChanges.append({ () -> () in
                    self.collectionView?.insertItemsAtIndexPaths([newIndexPath])
                })
            }
        case .Delete:
            if let indexPath = indexPath {
                objectChanges.append({ () -> () in
                    self.collectionView?.deleteItemsAtIndexPaths([indexPath])
                })
            }
        case .Update:
            if let indexPath = indexPath {
                objectChanges.append({ () -> () in
                    self.collectionView?.reloadItemsAtIndexPaths([indexPath])
                })
            }
        case .Move:
            if let indexPath = indexPath, let newIndexPath = newIndexPath {
                objectChanges.append({ () -> () in
                    // A cell must change its position means that this cell must be updated with the corresponding VPS.
                    if let cell = self.collectionView?.cellForItemAtIndexPath(indexPath) {
                        let VPS = self.fetchedResultsController.objectAtIndexPath(newIndexPath) as! OVHVPS
                        self.configureCell(cell, withVPS: VPS)
                    }
                    self.collectionView?.moveItemAtIndexPath(indexPath, toIndexPath: newIndexPath)
                })
            }
        }
    }
    
    
    // MARK: - Private methods
    
    private func configureCell(cell: UICollectionViewCell, withVPS VPS: OVHVPS) {
        let nameLabel = cell.viewWithTag(1) as! UILabel
        let imageView = cell.viewWithTag(2) as! UIImageView
        let loadingView = cell.viewWithTag(3) as! UIActivityIndicatorView
        
        nameLabel.text = VPS.displayName
        
        if VPS.isBusy() {
            imageView.alpha = 0.25
            nameLabel.alpha = 0.25
            loadingView.startAnimating()
        } else {
            imageView.alpha = 1.0
            nameLabel.alpha = 1.0
            loadingView.stopAnimating()
        }
        
        var color = UIColor.grayColor()
        if VPS.isRunning() {
            color = UIColor.greenColor()
        } else if VPS.isStopped() {
            color = UIColor.blackColor()
        }
        
        imageView.tintColor = color
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
    
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: "refreshVPS:", forControlEvents: .ValueChanged)
        
        if let refreshControl = refreshControl {
            collectionView?.addSubview(refreshControl)
            collectionView?.alwaysBounceVertical = true
        }
        
        do {
            try fetchedResultsController.performFetch()
        } catch let error {
            print("Failed to fetch VPS: \(error)")
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

