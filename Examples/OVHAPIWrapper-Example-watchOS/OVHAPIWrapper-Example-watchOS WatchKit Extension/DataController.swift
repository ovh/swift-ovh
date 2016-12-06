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
    
    fileprivate var VPSList = [VPS]()
    
    fileprivate var OVHAPI: OVHAPIWrapper?
    fileprivate let session: WCSession?
    
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
        sendDataWithKey("init", data: "" as AnyObject) { message in
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
    func rebootVPSWithName(_ VPSName: String, completionBlock: ((Error?) -> Void)?) {
        callAPIAction("reboot", onVPS: VPSName, completionBlock: completionBlock)
    }
    
    /**
     Start a VPS.
     */
    func startVPSWithName(_ VPSName: String, completionBlock: ((Error?) -> Void)?) {
        callAPIAction("start", onVPS: VPSName, completionBlock: completionBlock)
    }
    
    /**
     Stop a VPS.
     */
    func stopVPSWithName(_ VPSName: String, completionBlock: ((Error?) -> Void)?) {
        callAPIAction("stop", onVPS: VPSName, completionBlock: completionBlock)
    }
    
    
    // MARK: - Private methods
    
    /**
    Send some data to the watch.
    */
    fileprivate func sendDataWithKey(_ key: String, data: AnyObject, replyHandler: (([String:Any]) -> Void)?) {
        if let session = session, session.isReachable {
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
    fileprivate func updateAPICredentials(_ credentials: [String:AnyObject]) {
        let applicationKey = credentials["applicationKey"] as! String
        let applicationSecret = credentials["applicationSecret"] as! String
        let consumerKey = credentials["consumerKey"] as! String
        OVHAPI = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: applicationKey, applicationSecret: applicationSecret, consumerKey: consumerKey, timeout: 15)
        OVHAPI?.enableLogs = true
    }
    
    /**
     The VPS list is updated.
     */
    fileprivate func updadeVPSList(_ list: [[String:AnyObject]]) {
        VPSList.removeAll()
        
        for representation in list {
            let vps = VPS.VPSFromWatchRepresentation(representation)
            VPSList.append(vps)
        }
        
        DispatchQueue.main.async { () -> Void in
            self.delegate?.VPSListUpdated()
        }
    }
    
    /**
     A VPS is updated.
     */
    fileprivate func updadeVPS(_ representation: [String:AnyObject]) {
        let vps = VPS.VPSFromWatchRepresentation(representation)
        
        var index = -1
        if VPSList.count > 0 {
            for i in 0...VPSList.count {
                if VPSList[i].name == vps.name {
                    VPSList[i] = vps
                    index = i
                    break
                }
            }
        }
        
        DispatchQueue.main.async { () -> Void in
            self.delegate?.VPSUpdated(atIndex: index)
        }
    }
    
    /**
     Call API: action on VPS
     */
    fileprivate func callAPIAction(_ action: String, onVPS VPSName: String, completionBlock: ((Error?) -> Void)?) {
        // Closure to update the VPS busy state.
        let updateVPSWithName = { (name: String, busy: Bool) -> Void in
            DispatchQueue.main.async(execute: { () -> Void in
                if self.VPSList.count > 0 {
                    for i in 0...self.VPSList.count {
                        var vps = self.VPSList[i]
                        if vps.name == VPSName {
                            vps.busy = busy
                            self.VPSList[i] = vps
                            
                            self.delegate?.VPSUpdated(atIndex: i)
                            break
                        }
                    }
                }
            })
        }
        
        updateVPSWithName(VPSName, true)
        
        // Launch the request.
        OVHAPI?.post("/vps/\(VPSName)/\(action)") { result, error, request, response in
            
            // Defered actions: call the completion block.
            var completionError: Error?
            defer {
                if let _ = completionError {
                    updateVPSWithName(VPSName, false)
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
                completionError = OVHAPIError.invalidRequestResponse
                return
            }
            
            // Notify the iOS application.
            self.sendDataWithKey("newTask", data: ["vps": VPSName, "task": result] as AnyObject, replyHandler: { message -> Void in
                print("Receive response from iOS application: \(message)")
            })
        }
    }
    
    
    // MARK: - WCSessionDelegate methods
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
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
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("Receive application context from iOS application: \(applicationContext)")
        
        let userDefaults = UserDefaults.standard
        userDefaults.set(applicationContext, forKey: "glance")
        if userDefaults.synchronize() {
            print("Glance data saved.")
        } else {
            print("Can not save the glance data.")
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("iOS application reachability changed.")
        
        if OVHAPI == nil {
            initializeData()
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        
    }
    
    
    // MARK: - Lifecycle
    
    override init() {
        if WCSession.isSupported() {
            session = WCSession.default()
        } else {
            session = nil
        }
        
        super.init()
        
        session?.delegate = self
        session?.activate()
    }
    
}

