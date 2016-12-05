//
//  WatchSessionManager.swift
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


protocol WatchSessionManagerDelegate {
    func APICredentials() -> [String:AnyObject]
    func VPSList() -> [[String:AnyObject]]
    func glanceData() -> [String:AnyObject]
    func complicationData() -> [String:AnyObject]
    func loadNewVPSTask(VPSName: String, task: [String:AnyObject])
}


final class WatchSessionManager: NSObject, WCSessionDelegate {
    
    // MARK: - Singleton
    
    static let sharedManager = WatchSessionManager()
    
    
    // MARK: - Properties
    
    var delegate: WatchSessionManagerDelegate?
    
    private let session: WCSession?
    private let queue: dispatch_queue_t = dispatch_queue_create("com.ovh.OVHAPIWrapper-Example-watchOS.watchos", nil)
    
    private var validSession: WCSession? {
        if let session = session where session.paired && session.watchAppInstalled {
            return session
        }
        
        return nil
    }
    
    private var APICredentials: [String:AnyObject]? {
        return delegate?.APICredentials()
    }
    
    private var VPSList: [[String:AnyObject]]? {
        return delegate?.VPSList()
    }
    
    private var glanceData: [String:AnyObject]? {
        return delegate?.glanceData()
    }
    
    private var complicationData: [String:AnyObject]? {
        return delegate?.complicationData()
    }
    
    
    // MARK: - Public methods
    
    /**
    Send to the watch the updated OVH API credentials.
    */
    func updateAPICredentials() {
        if let credentials = APICredentials {
            dispatch_async(queue) { () -> Void in
                self.sendDataWithKey("credentials", andData: credentials)
            }
        }
    }
    
    /**
     Send to the watch the updated list of VPS.
     */
    func updateVPSList() {
        if let list = VPSList {
            dispatch_async(queue) { () -> Void in
                self.sendDataWithKey("VPSlist", andData: list)
            }
        }
    }
    
    /**
     Send to the watch the updated state of a VPS.
     */
    func updateVPS(VPS: [String:AnyObject], withOldRepresentation oldVPS: [String:AnyObject]) {
        if VPS["busy"] as? Bool == oldVPS["busy"] as? Bool && VPS["state"] as? String == oldVPS["state"] as? String && VPS["displayName"] as? String == oldVPS["displayName"] as? String {
            return
        }
        
        dispatch_async(queue) { () -> Void in
            self.sendDataWithKey("VPS", andData: VPS as AnyObject)
        }
    }
    
    /**
     Send to the watch the updated glance data.
     */
    func updateGlance() {
        dispatch_async(queue) { () -> Void in
            if let session = self.validSession, let data = self.delegate?.glanceData() {
                do {
                    try session.updateApplicationContext(data)
                    print("Send application context: \(data)")
                } catch let error {
                    print("Can not send glance data: \(error)")
                }
            } else {
                print("Watch OS glance is not available.")
            }
        }
    }
    
    /**
     Send to the watch the updated complication data.
     */
    func updateComplication() {
        dispatch_async(queue) { () -> Void in
            if let session = self.validSession where session.complicationEnabled, let data = self.delegate?.complicationData() {
                session.transferCurrentComplicationUserInfo(data)
                print("Send complication data: \(data)")
            } else {
                print("Watch OS complication is not available.")
            }
        }
    }
    
    
    // MARK: - Private methods
    
    /**
     Send some data to the watch.
     */
    private func sendDataWithKey(key: String, andData data: AnyObject) {
        if let session = validSession where session.reachable {
            session.sendMessage([key : data], replyHandler: { response -> Void in
                print("Response received from watch application: \(response)")
                }, errorHandler: { error -> Void in
                print("Error send message to the watch: \(error)")
            })
            print("Send message to watch: \(key) = \(data)")
        } else {
            print("Watch OS application is not available.")
        }
    }
    
    
    // MARK: - WCSessionDelegate methods
    
    func session(session: WCSession, didReceiveMessage message: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {
        print("Receive message from watch application: \(message)")
        
        var response = [String : AnyObject]()
        
        for (key, value) in message {
            switch key {
            case "init":
                // Get the API credentials and the VPS list.
                if let credentials = APICredentials, let list = VPSList {
                    response = ["credentials": credentials, "VPSlist": list]
                }
            case "newTask":
                if let data = value as? [String:AnyObject] {
                    let VPSName = data["vps"] as! String
                    let task = data["task"] as! [String:AnyObject]
                    delegate?.loadNewVPSTask(VPSName, task: task)
                }
            default: break
            }
        }
        
        replyHandler(response)
    }
    
    func session(session: WCSession, activationDidCompleteWithState activationState: WCSessionActivationState, error: NSError?) {
        
    }
    
    func sessionDidBecomeInactive(session: WCSession) {
        
    }
    
    func sessionDidDeactivate(session: WCSession) {
        
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
