//
//  InterfaceController.swift
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

import WatchKit
import Foundation
import OVHAPIWrapper

class InterfaceController: WKInterfaceController, DataControllerDelegate {
    
    // MARK: - UI elements

    @IBOutlet var table: WKInterfaceTable!
    
    
    // MARK: - Properties
    
    fileprivate let dataController = DataController.sharedController
    
    
    // MARK: - DataController delegate methods
    
    /**
    The VPS are updated, the table ust be updated.
    */
    func VPSListUpdated() {
        configureTable()
    }
    
    /**
     A VPS is updated, the row ust be updated.
     */
    func VPSUpdated(atIndex index: Int) {
        configureTableRowAtIndex(index)
    }
    
    
    // MARK: - Private methods
    
    /**
    Configure the whole table.
    */
    fileprivate func configureTable() {
        let countOfRows = dataController.count
        table.setNumberOfRows(countOfRows, withRowType: "VPSRow")
        
        for index in 0..<countOfRows {
            configureTableRowAtIndex(index)
        }
    }
    
    /**
     Configure a single table row.
     */
    fileprivate func configureTableRowAtIndex(_ index: Int) {
        if let controller = table.rowController(at: index) as? VPSRowController {
            controller.vps = dataController[index]
        }
    }
    
    
    // MARK: - Table view methods
    
    override func table(_ table: WKInterfaceTable, didSelectRowAt rowIndex: Int) {
        let VPS = dataController[rowIndex]
        
        guard !VPS.busy else {
            return
        }
        
        let completionBlock = { (error: Error?) -> Void in
            if let error = error {
                let action = WKAlertAction(title: "Close", style: .cancel, handler: { () -> Void in
                })
                
                var title = "can not execute action"
                if let error = error as? OVHAPIError {
                    title = error.description
                }
                self.presentAlert(withTitle: title, message: nil, preferredStyle: .alert, actions: [action])
            }
        }
        
        var actions = [WKAlertAction]()
        
        if VPS.state != VPSState.running {
            let action = WKAlertAction(title: "Start", style: .default, handler: { () -> Void in
                self.dataController.startVPSWithName(VPS.name!, completionBlock: completionBlock)
            })
            actions.append(action)
        }
        
        if VPS.state != VPSState.stopped {
            let stopAction = WKAlertAction(title: "Stop", style: .destructive, handler: { () -> Void in
                self.dataController.stopVPSWithName(VPS.name!, completionBlock: completionBlock)
            })
            actions.append(stopAction)
            
            let rebootAction = WKAlertAction(title: "Reboot", style: .default, handler: { () -> Void in
                self.dataController.rebootVPSWithName(VPS.name!, completionBlock: completionBlock)
            })
            actions.append(rebootAction)
        }
        
        presentAlert(withTitle: VPS.displayName, message: nil, preferredStyle: .actionSheet, actions: actions)
    }
    
    
    // MARK: - Lifecycle
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.
        configureTable()
        
        dataController.delegate = self
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }
}
