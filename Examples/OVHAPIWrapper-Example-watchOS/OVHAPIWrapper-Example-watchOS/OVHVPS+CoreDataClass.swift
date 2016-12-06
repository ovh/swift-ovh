//
//  OVHVPS+CoreDataClass.swift
//  
//
//  Created by Cyril on 06/12/2016.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


public class OVHVPS: NSManagedObject {
    func isBusy() -> Bool {
        return (state != OVHVPSState.running.rawValue && state != OVHVPSState.stopped.rawValue) || currentTask != nil //|| waitingTask
    }
    
    func isRunning() -> Bool {
        return state == OVHVPSState.running.rawValue
    }
    
    func isStopped() -> Bool {
        return state == OVHVPSState.stopped.rawValue
    }
    
    func isStateUnknown() -> Bool {
        return state == OVHVPSState.unknown.rawValue
    }
    
    func watchRepresentation() -> [String:AnyObject] {
        var representation = [String:AnyObject]()
        
        if let name = name {
            representation["name"] = name as AnyObject?
        }
        if let displayName = displayName {
            representation["displayName"] = displayName as AnyObject?
        }
        if let state = state {
            representation["state"] = state as AnyObject?
        }
        
        representation["busy"] = isBusy() as AnyObject?
        
        return representation
    }
}

public enum OVHVPSState : String {
    case installing, maintenance, rebooting, running, stopped, stopping, upgrading, unknown
}
