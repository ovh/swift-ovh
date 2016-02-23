//
//  DataController.swift
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
import WatchConnectivity
import OVHAPIWrapper


protocol DataControllerDelegate {
    func VPSListUpdated()
    func VPSUpdated(atIndex index: Int)
}

final class DataController: NSObject, WCSessionDelegate {
    
    // MARK: - Singleton
    
    static let sharedController = DataController()
    
    
    // MARK: - Properties
    
    var delegate: DataControllerDelegate?
    
    private var VPSList = [VPS]()
    
    private var OVHAPI: OVHAPIWrapper?
    private let session: WCSession?
    
    var count: Int {
        return VPSList.count
    }
    
    subscript(index: Int) -> VPS {
        return VPSList[index]
    }
    
    
    // MARK: - Public methods
    
    /**
     Ask the iOS application for the intial data.
     */
    func initializeData() {
        sendDataWithKey("init", data: "") { message in
            print("Receive response from iOS application: \(message)")
            
            for (key, value) in message {
                switch key {
                case "credentials":
                    if let credentials = value as? [String:AnyObject] {
                        self.updateAPICredentials(credentials)
                    }
                case "VPSlist":
                    if let list = value as? [[String:AnyObject]] {
                        self.updadeVPSList(list)
                    }
                default: break
                }
            }
        }
    }
    
    /**
     Reboot a VPS.
     */
    func rebootVPSWithName(VPSName: String, completionBlock: ((ErrorType?) -> Void)?) {
        callAPIAction("reboot", onVPS: VPSName, completionBlock: completionBlock)
    }
    
    /**
     Start a VPS.
     */
    func startVPSWithName(VPSName: String, completionBlock: ((ErrorType?) -> Void)?) {
        callAPIAction("start", onVPS: VPSName, completionBlock: completionBlock)
    }
    
    /**
     Stop a VPS.
     */
    func stopVPSWithName(VPSName: String, completionBlock: ((ErrorType?) -> Void)?) {
        callAPIAction("stop", onVPS: VPSName, completionBlock: completionBlock)
    }
    
    
    // MARK: - Private methods
    
    /**
    Send some data to the watch.
    */
    private func sendDataWithKey(key: String, data: AnyObject, replyHandler: (([String:AnyObject]) -> Void)?) {
        if let session = session where session.reachable {
            session.sendMessage([key : data], replyHandler: replyHandler, errorHandler: { error -> Void in
                print("Error send message to the iOS app: \(error)")
            })
            print("Send message to iOS app: \(key) = \(data)")
        } else {
            print("iOS application is not available.")
        }
    }
    
    /**
     The credentials are updated.
     */
    private func updateAPICredentials(credentials: [String:AnyObject]) {
        let applicationKey = credentials["applicationKey"] as! String
        let applicationSecret = credentials["applicationSecret"] as! String
        let consumerKey = credentials["consumerKey"] as! String
        OVHAPI = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: applicationKey, applicationSecret: applicationSecret, consumerKey: consumerKey, timeout: 15)
        OVHAPI?.enableLogs = true
    }
    
    /**
     The VPS list is updated.
     */
    private func updadeVPSList(list: [[String:AnyObject]]) {
        VPSList.removeAll()
        
        for representation in list {
            let vps = VPS.VPSFromWatchRepresentation(representation)
            VPSList.append(vps)
        }
        
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.delegate?.VPSListUpdated()
        }
    }
    
    /**
     A VPS is updated.
     */
    private func updadeVPS(representation: [String:AnyObject]) {
        let vps = VPS.VPSFromWatchRepresentation(representation)
        
        var index = -1
        for var i = 0; i < VPSList.count && index == -1; i++ {
            if VPSList[i].name == vps.name {
                VPSList[i] = vps
                index = i
            }
        }
        
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.delegate?.VPSUpdated(atIndex: index)
        }
    }
    
    /**
     Call API: action on VPS
     */
    private func callAPIAction(action: String, onVPS VPSName: String, completionBlock: ((ErrorType?) -> Void)?) {
        // Closure to update the VPS busy state.
        let updateVPSWithName = { (name: String, setBusy busy: Bool) -> Void in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                var found = false
                for var i = 0; i < self.VPSList.count && !found; i++ {
                    var vps = self.VPSList[i]
                    if vps.name == VPSName {
                        found = true
                        vps.busy = busy
                        self.VPSList[i] = vps
                        
                        self.delegate?.VPSUpdated(atIndex: i)
                    }
                }
            })
        }
        
        updateVPSWithName(VPSName, setBusy: true)
        
        // Launch the request.
        OVHAPI?.post("/vps/\(VPSName)/\(action)") { result, error, request, response in
            
            // Defered actions: call the completion block.
            var completionError: ErrorType?
            defer {
                if let _ = completionError {
                    updateVPSWithName(VPSName, setBusy: false)
                }
                if let block = completionBlock {
                    block(completionError)
                }
            }
            
            // Handle the error.
            guard error == nil else {
                completionError = error
                return
            }
            
            // Handle invalid response.
            guard result is [String:AnyObject] else {
                completionError = OVHAPIError.InvalidRequestResponse
                return
            }
            
            // Notify the iOS application.
            self.sendDataWithKey("newTask", data: ["vps":VPSName, "task":result as! [String:AnyObject]], replyHandler: { message -> Void in
                print("Receive response from iOS application: \(message)")
            })
        }
    }
    
    
    // MARK: - WCSessionDelegate methods
    
    func session(session: WCSession, didReceiveMessage message: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {
        print("Receive message from iOS application: \(message)")
        
        for (key, value) in message {
            switch key {
            case "credentials":
                if let credentials = value as? [String:AnyObject] {
                    updateAPICredentials(credentials)
                }
            case "VPSlist":
                if let list = value as? [[String:AnyObject]] {
                    updadeVPSList(list)
                }
            case "VPS":
                if let representation = value as? [String:AnyObject] {
                    updadeVPS(representation)
                }
            default: break
            }
        }
        
        replyHandler([String:AnyObject]())
    }
    
    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
        print("Receive application context from iOS application: \(applicationContext)")
        
        let userDefaults = NSUserDefaults.standardUserDefaults()
        userDefaults.setObject(applicationContext, forKey: "glance")
        if userDefaults.synchronize() {
            print("Glance data saved.")
        } else {
            print("Can not save the glance data.")
        }
    }
    
    func sessionReachabilityDidChange(session: WCSession) {
        print("iOS application reachability changed.")
        
        if OVHAPI == nil {
            initializeData()
        }
    }
    
    
    // MARK: - Lifecycle
    
    override init() {
        if WCSession.isSupported() {
            session = WCSession.defaultSession()
        } else {
            session = nil
        }
        
        super.init()
        
        session?.delegate = self
        session?.activateSession()
    }
    
}

