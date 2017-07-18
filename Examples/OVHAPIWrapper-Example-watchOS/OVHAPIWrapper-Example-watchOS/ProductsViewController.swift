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
    
    lazy fileprivate var fetchedResultsController: NSFetchedResultsController<OVHVPS> = { () -> NSFetchedResultsController<OVHVPS> in
        let fetchRequest: NSFetchRequest<OVHVPS> = OVHVPS.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "displayName", ascending: true)]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: CoreDataManager.sharedManager.managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        
        return fetchedResultsController
    }()
    
    typealias changes = () -> ()
    fileprivate var sectionsChanges = [changes]()
    fileprivate var objectChanges = [changes]()

    
    // MARK: - UI elements
    
    @IBOutlet weak var authenticateButton: UIBarButtonItem!
    fileprivate var refreshControl: UIRefreshControl?
    
    
    // MARK: - Actions
    
    @IBAction func authenticate(_ sender: UIBarButtonItem) {
        sender.isEnabled = false;
        
        OVHVPSController.sharedController.OVHAPI.requestCredentials(withAccessRules: [OVHAPIAccessRule(method: .get, path: "/vps*"), OVHAPIAccessRule(method: .post, path: "/vps*")], redirection: "https://www.ovh.com/fr/") { (viewController, error) -> Void in
            guard error == nil else {
                self.presentError(error)
                sender.isEnabled = true
                return
            }
            
            if let viewController = viewController {
                viewController.completion = { consumerKeyIsValidated in
                    sender.isEnabled = true
                    
                    if consumerKeyIsValidated {
                        self.refreshControl?.beginRefreshing()
                        self.collectionView?.contentOffset = CGPoint(x: 0, y: -self.refreshControl!.frame.size.height);
                        self.refreshVPS(self.refreshControl!)
                        
                        // Send to the watch the updated credentials.
                        WatchSessionManager.sharedManager.updateAPICredentials()
                    }
                }
                
                self.present(viewController, animated: true, completion: nil)
            }
        }
    }
    
    @IBAction func refreshVPS(_ sender: UIRefreshControl) {
        OVHVPSController.sharedController.loadVPS(withBlock: { error in
            self.presentError(error)
            self.refreshControl?.endRefreshing()
        })
    }
    
    
    // MARK: - UICollectionViewController delegate methods
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        if let count = fetchedResultsController.sections?.count {
            return count
        }
        
        return 0
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if let sectionInfo = fetchedResultsController.sections?[section] {
            return sectionInfo.numberOfObjects
        }
        
        return 0
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VPSCell", for: indexPath)
        let VPS = fetchedResultsController.object(at: indexPath)
        
        configureCell(cell, withVPS: VPS)
        
        return cell
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let VPS = fetchedResultsController.object(at: indexPath)
        
        // No action on the busy VPS.
        guard !VPS.isBusy() && !VPS.isStateUnknown() else {
            return
        }
        
        let VPSName = VPS.name!
        
        // Create the alert controller to present to the user.
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        // Add the 'start' action.
        if VPS.isStopped() {
            let startAction = UIAlertAction(title: "Start", style: .default, handler: { action -> Void in
                OVHVPSController.sharedController.startVPS(withName: VPSName, andCompletionBlock: { (task, error) in
                    self.presentError(error)
                })
            })
            alertController.addAction(startAction)
        }
        
        if VPS.isRunning() {
            // Add the 'reboot' action.
            let rebootAction = UIAlertAction(title: "Reboot", style: .default, handler: { action -> Void in
                OVHVPSController.sharedController.rebootVPS(withName: VPSName, andCompletionBlock: { (task, error) in
                    self.presentError(error)
                })
            })
            alertController.addAction(rebootAction)
            
            // Add the 'stop' action.
            let stopAction = UIAlertAction(title: "Stop", style: .destructive, handler: { action -> Void in
                OVHVPSController.sharedController.stopVPS(withName: VPSName, andCompletionBlock: { (task, error) in
                    self.presentError(error)
                })
            })
            alertController.addAction(stopAction)
        }
        
        // Add the 'cancel' action.
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { action -> Void in
            alertController.dismiss(animated: true, completion: nil)
        })
        alertController.addAction(cancelAction)
        
        // A popover is created on the devices supporting this feature (iPad).
        if let popoverPresentationController = alertController.popoverPresentationController {
            alertController.modalPresentationStyle = .popover
            
            if let cell = collectionView.cellForItem(at: indexPath) {
                popoverPresentationController.sourceView = cell
                popoverPresentationController.sourceRect = cell.bounds
            }
        }
        
        // Present the alert controller to the user.
        present(alertController, animated: true, completion: nil)
    }
    
    
    // MARK: - FetchedController delegate methods
    
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        sectionsChanges.removeAll()
        objectChanges.removeAll()
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
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
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        let sections = IndexSet(integer: sectionIndex)
        
        switch (type) {
        case .insert:
            sectionsChanges.append({ () -> () in
                self.collectionView?.insertSections(sections)
            })
        case .delete:
            sectionsChanges.append({ () -> () in
                self.collectionView?.deleteSections(sections)
            })
        case .update:
            sectionsChanges.append({ () -> () in
                self.collectionView?.reloadSections(sections)
            })
        case .move:
            break
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch (type) {
        case .insert:
            if let newIndexPath = newIndexPath {
                objectChanges.append({ () -> () in
                    self.collectionView?.insertItems(at: [newIndexPath])
                })
            }
        case .delete:
            if let indexPath = indexPath {
                objectChanges.append({ () -> () in
                    self.collectionView?.deleteItems(at: [indexPath])
                })
            }
        case .update:
            if let indexPath = indexPath {
                objectChanges.append({ () -> () in
                    self.collectionView?.reloadItems(at: [indexPath])
                })
            }
        case .move:
            if let indexPath = indexPath, let newIndexPath = newIndexPath {
                objectChanges.append({ () -> () in
                    // A cell must change its position means that this cell must be updated with the corresponding VPS.
                    if let cell = self.collectionView?.cellForItem(at: indexPath) {
                        let VPS = self.fetchedResultsController.object(at: newIndexPath)
                        self.configureCell(cell, withVPS: VPS)
                    }
                    self.collectionView?.moveItem(at: indexPath, to: newIndexPath)
                })
            }
        }
    }
    
    
    // MARK: - Private methods
    
    fileprivate func configureCell(_ cell: UICollectionViewCell, withVPS VPS: OVHVPS) {
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
        
        var color = UIColor.gray
        if VPS.isRunning() {
            color = UIColor(red: 0.0, green: 0.8, blue: 0.2, alpha: 1.0)
        } else if VPS.isStopped() {
            color = UIColor.black
        }
        
        imageView.tintColor = color
    }
    
    fileprivate func presentError(_ error: Error?) {
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
    
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(ProductsViewController.refreshVPS(_:)), for: .valueChanged)
        
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

