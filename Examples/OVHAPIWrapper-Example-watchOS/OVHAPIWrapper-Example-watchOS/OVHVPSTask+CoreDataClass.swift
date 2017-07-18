//
//  OVHVPSTask+CoreDataClass.swift
//  
//
//  Created by Cyril on 06/12/2016.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


public class OVHVPSTask: NSManagedObject {
    func isFinished() -> Bool {
        return state != OVHVPSTaskState.todo.rawValue && state != OVHVPSTaskState.doing.rawValue && state != OVHVPSTaskState.waitingAck.rawValue && state != OVHVPSTaskState.paused.rawValue
    }
    
    func isPaused() -> Bool {
        return state == OVHVPSTaskState.paused.rawValue
    }
}

public enum OVHVPSTaskState : String {
    case blocked, cancelled, doing, done, error, paused, todo, waitingAck
}

public enum OVHVPSTaskType : String {
    case addVeeamBackupJob, changeRootPassword, createSnapshot, deleteSnapshot, deliverVm, internalTask, openConsoleAccess, provisioningAdditionalIp, reOpenVm, rebootVm, reinstallVm, removeVeeamBackup, restoreFullVeeamBackup, restoreVeeamBackup, revertSnapshot, setMonitoring, setNetboot, startVm, stopVm, upgradeVm
}
