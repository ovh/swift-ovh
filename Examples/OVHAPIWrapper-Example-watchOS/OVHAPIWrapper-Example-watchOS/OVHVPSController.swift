//
//  OVHVPSController.swift
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
import CoreData
import OVHAPIWrapper

final class OVHVPSController: WatchSessionManagerDelegate {
    
    // MARK: - Singleton
    
    static let sharedController = OVHVPSController()
    
    
    // MARK: - Structs
    
    private struct RunningTask {
        let id: Int64
        let running: Bool
    }
    
    
    // MARK: - Properties
    
    // The OVH API wrapper, used to manage the calls to the API.
    let OVHAPI: OVHAPIWrapper
    
    // Manage the CoreData layer.
    private let coreDataController = CoreDataManager.sharedManager
    
    // The running tasks are tracked to be refreshed.
    private var runningTasks = [String:RunningTask]()
    private var runningTasksTimer: NSTimer?
    private let runningTasksTimerTimeInterval: NSTimeInterval = 15
    
    // The properties (state) of the VPS are tracked to be refreshed.
    private var runningProperties = [String:Bool]()
    private var runningPropertiesTimer: NSTimer?
    private let runningPropertiesTimerTimeInterval: NSTimeInterval = 15
    
    // The VPS are refreshed every hour.
    private var runningVPSTimer: NSTimer?
    private let runningVPSTimerTimeInterval: NSTimeInterval = 60*60
    
    
    // MARK: - Data loading
    
    /**
    Load all the VPS from the OVH API.
    */
    func loadVPSWithBlock(completionBlock: ((ErrorType?) -> Void)?) {
        // Invalidate the current timer.
        if let timer = runningVPSTimer {
            timer.invalidate()
        }
        
        // Launch the request.
        OVHAPI.get("/vps") { (result, error, request, response) -> Void in
            
            // The process is run in the background to not block the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in
                
                // Defered actions: call the completion block.
                var completionError: ErrorType?
                defer {
                    if let block = completionBlock {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            block(completionError)
                        })
                    }
                    
                    // Start the timer.
                    var fireDateTimeInterval = self.runningVPSTimerTimeInterval
                    if let _ = completionError {
                        fireDateTimeInterval = 30
                    }
                    self.runningVPSTimer = NSTimer(fireDate: NSDate(timeIntervalSinceNow: fireDateTimeInterval), interval: self.runningTasksTimerTimeInterval, target: self, selector: "refreshVPS", userInfo: nil, repeats: false)
                    if let timer = self.runningVPSTimer {
                        NSRunLoop.mainRunLoop().addTimer(timer, forMode: NSRunLoopCommonModes)
                    }
                }
                
                // Handle the error.
                guard error == nil else {
                    completionError = error
                    return
                }
                
                // Handle invalid response.
                guard result is [String] else {
                    completionError = OVHAPIError.InvalidRequestResponse
                    return
                }
                
                // Handle the VPS: save them and load the properties.
                if let allVPS = (result as? [String]) {
                    
                    let context = self.coreDataController.newManagedObjectContext()
                    context.performBlockAndWait({ () -> Void in
                        do {
                            // Get all the saved VPS.
                            let fetchRequest = NSFetchRequest(entityName: "OVHVPS")
                            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
                            fetchRequest.includesSubentities = false
                            fetchRequest.propertiesToFetch = ["name"]
                            
                            var fetchedVPS = try context.executeFetchRequest(fetchRequest)
                            
                            for VPS in allVPS {
                                let VPSName = VPS as String
                                
                                // Is this VPS already saved?
                                var found = false
                                for var i = 0; i < fetchedVPS.count && !found; i++ {
                                    if fetchedVPS[i].name == VPSName {
                                        found = true
                                        fetchedVPS.removeAtIndex(i)
                                    }
                                }
                                
                                // If not saved create it.
                                if !found {
                                    let VPSEntity = NSEntityDescription.insertNewObjectForEntityForName("OVHVPS", inManagedObjectContext: context) as! OVHVPS
                                    VPSEntity.name = VPSName
                                    VPSEntity.displayName = VPSName
                                    VPSEntity.state = OVHVPSState.unknown.rawValue
                                    
                                    self.coreDataController.saveManagedObjectContext(context)
                                    
                                    // Load the properties.
                                    self.reloadVPSPropertiesWithName(VPSName) { properties, error in
                                        if let properties = properties, let state = properties["state"] as? String {
                                            if state != OVHVPSState.running.rawValue && state != OVHVPSState.stopped.rawValue {
                                                self.loadVPSTaskWithVPSName(VPSName, completionBlock: nil)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Delete the VPS that are not returned by the request.
                            for VPS in fetchedVPS {
                                context.deleteObject(VPS as! NSManagedObject)
                            }
                            
                            self.coreDataController.saveManagedObjectContext(context)
                            
                            // Send to the watch the updated list of VPS.
                            WatchSessionManager.sharedManager.updateVPSList()
                            WatchSessionManager.sharedManager.updateGlance()
                            WatchSessionManager.sharedManager.updateComplication()
                        } catch let error {
                            completionError = error
                            print("Failed to fetch VPS: \(error)")
                        }
                    })
                }
            })
        }
    }
    
    /**
     Load the properties of a VPS from the OVH API.
     */
    func reloadVPSPropertiesWithName(VPSName: String, completionBlock: (([String:AnyObject]?, ErrorType?) -> Void)?) {
        // Track this running task.
        runningProperties[VPSName] = true
        
        // Launch the request.
        OVHAPI.get("/vps/\(VPSName)") { (result, error, request, response) -> Void in
            
            // The process is run in the background to not block the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in
                
                // Defered actions: call the completion block.
                var completionProperties : [String:AnyObject]?
                var completionError: ErrorType?
                defer {
                    if let block = completionBlock {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            block(completionProperties, completionError)
                        })
                    }
                    
                    if let _ = self.runningProperties[VPSName] {
                        self.runningProperties[VPSName] = false
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
                
                // Save the properties.
                if let VPSProperties = (result as? [String:AnyObject]) {
                    
                    let context = self.coreDataController.newManagedObjectContext()
                    context.performBlockAndWait({ () -> Void in
                        var keepTrackingTask = false
                        
                        do {
                            let fetchRequest = NSFetchRequest(entityName: "OVHVPS")
                            fetchRequest.predicate = NSPredicate(format: "%K = %@", "name", VPSName)
                            fetchRequest.fetchLimit = 1
                            
                            let fetchedVPS = try context.executeFetchRequest(fetchRequest)
                            if fetchedVPS.count > 0 {
                                let VPS = fetchedVPS.first as! OVHVPS
                                let oldWatchRepresentation = VPS.watchRepresentation()
                                
                                if let displayName = VPSProperties["displayName"] as? String {
                                    VPS.displayName = displayName
                                }
                                VPS.offerType = VPSProperties["offerType"] as? String
                                VPS.state = VPSProperties["state"] as? String
                                
                                completionProperties = VPSProperties
                                
                                keepTrackingTask = VPS.isBusy()
                                
                                // Send to the watch the updated state of VPS.
                                WatchSessionManager.sharedManager.updateVPS(VPS.watchRepresentation(), withOldRepresentation: oldWatchRepresentation)
                                WatchSessionManager.sharedManager.updateGlance()
                                WatchSessionManager.sharedManager.updateComplication()
                            }
                        } catch let error {
                            completionError = error
                            print("Failed to fetch VPS: \(error)")
                        }
                        
                        if !keepTrackingTask {
                            self.runningProperties.removeValueForKey(VPSName)
                        }
                        
                        self.coreDataController.saveManagedObjectContext(context)
                    })
                }
            })
        }
    }
    
    /**
     Load the tasks of a VPS from the OVH API.
     */
    func loadVPSTaskWithVPSName(VPSName: String, completionBlock: (([String:AnyObject]?, ErrorType?) -> Void)?) {
        // Launch the request.
        OVHAPI.get("/vps/\(VPSName)/tasks") { (result, error, request, response) -> Void in
            
            // The process is run in the background to not block the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in
                
                // Defered actions: call the completion block.
                var completionVPSTask: [String:AnyObject]?
                var completionError: ErrorType?
                defer {
                    if let block = completionBlock {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            block(completionVPSTask, completionError)
                        })
                    }
                }
                
                // Handle the error.
                guard error == nil else {
                    completionError = error
                    return
                }
                
                // Handle invalid response.
                guard result is [String] else {
                    completionError = OVHAPIError.InvalidRequestResponse
                    return
                }
                
                // Save the properties.
                if let VPSTaskIDs = (result as? [String]) {
                    if VPSTaskIDs.count > 0 {
                        if let VPSTaskIDObject = VPSTaskIDs.first, let VPSTaskID = Int64(VPSTaskIDObject) {
                            
                            // As we have a defer block and the following API call is asynchronous,
                            // a semaphore is used in order to wait to not return now.
                            let semaphore = dispatch_semaphore_create(0)
                            
                            self.reloadVPSTaskWithVPSName(VPSName, taskId: VPSTaskID, completionBlock: { (VPSTask, error) -> Void in
                                completionVPSTask = VPSTask
                                completionError = error
                                dispatch_semaphore_signal(semaphore)
                            })
                            
                            // Waiting for the end of call "/vps/x/task/y"
                            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
                        }
                    }
                }
            })
        }
    }
    
    /**
     Load the task with ID of a VPS from the OVH API.
     */
    func reloadVPSTaskWithVPSName(VPSName: String, taskId: Int64, completionBlock: (([String:AnyObject]?, ErrorType?) -> Void)?) {
        // Track this running task.
        runningTasks[VPSName] = RunningTask(id: taskId, running: true)
        
        // Launch the request.
        self.OVHAPI.get("/vps/\(VPSName)/tasks/\(taskId)") { (result, error, request, response) -> Void in
            
            // The process is running in the background to not block the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in
                
                // Defered actions: call the completion block.
                var completionVPSTask: [String:AnyObject]?
                var completionError: ErrorType?
                defer {
                    if let block = completionBlock {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            block(completionVPSTask, completionError)
                        })
                    }
                    
                    if var task = self.runningTasks[VPSName] {
                        self.runningTasks[VPSName] = RunningTask(id: taskId, running: false)
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
                
                // Save the task.
                if let VPSTask = (result as? [String:AnyObject]) {
                    
                    let context = self.coreDataController.newManagedObjectContext()
                    context.performBlockAndWait({ () -> Void in
                        var keepTrackingTask = false
                        
                        do {
                            let fetchRequest = NSFetchRequest(entityName: "OVHVPS")
                            fetchRequest.predicate = NSPredicate(format: "%K = %@", "name", VPSName)
                            fetchRequest.fetchLimit = 1
                            
                            let fetchedVPS = try context.executeFetchRequest(fetchRequest)
                            if fetchedVPS.count > 0 {
                                let VPS = fetchedVPS.first as! OVHVPS
                                let VPSTaskId = ((VPSTask["id"] as? NSNumber)?.longLongValue)!
                                let VPSTaskProgress = ((VPSTask["progress"] as? NSNumber)?.longLongValue)!
                                let VPSTaskType = VPSTask["type"] as! String
                                let VPSTaskState = VPSTask["state"] as! String
                                
                                let oldWatchRepresentation = VPS.watchRepresentation()
                                
                                if VPS.currentTask?.id == VPSTaskId {
                                    if VPS.currentTask?.state != VPSTaskState {
                                        VPS.currentTask?.state = VPSTaskState
                                    }
                                    if VPS.currentTask?.progress != VPSTaskProgress {
                                        VPS.currentTask?.progress = VPSTaskProgress
                                    }
                                } else {
                                    let VPSTaskEntity = NSEntityDescription.insertNewObjectForEntityForName("OVHVPSTask", inManagedObjectContext: context) as! OVHVPSTask
                                    VPSTaskEntity.id = VPSTaskId
                                    VPSTaskEntity.type = VPSTaskType
                                    VPSTaskEntity.state = VPSTaskState
                                    VPSTaskEntity.progress = VPSTaskProgress
                                    
                                    VPS.currentTask = VPSTaskEntity
                                }
                                
                                if let task = VPS.currentTask {
                                    if task.isFinished() {
                                        VPS.currentTask = nil
                                        
                                        self.reloadVPSPropertiesWithName(VPSName, completionBlock: nil)
                                    } else {
                                        keepTrackingTask = true
                                    }
                                }
                                
                                VPS.waitingTask = false
                                
                                completionVPSTask = VPSTask
                                
                                // Send to the watch the updated state of VPS.
                                WatchSessionManager.sharedManager.updateVPS(VPS.watchRepresentation(), withOldRepresentation: oldWatchRepresentation)
                                WatchSessionManager.sharedManager.updateGlance()
                                WatchSessionManager.sharedManager.updateComplication()
                            }
                        } catch let error {
                            completionError = error
                            print("Failed to fetch VPS: \(error)")
                        }
                        
                        if !keepTrackingTask {
                            self.runningTasks.removeValueForKey(VPSName)
                        }
                        
                        self.coreDataController.saveManagedObjectContext(context)
                    })
                }
            })
        }
    }
    
    /**
     Reboot a VPS.
     */
    func rebootVPSWithName(VPSName: String, completionBlock: (([String:AnyObject]?, ErrorType?) -> Void)?) {
        callAPIAction("reboot", onVPS: VPSName, completionBlock: completionBlock)
    }
    
    /**
     Start a VPS.
     */
    func startVPSWithName(VPSName: String, completionBlock: (([String:AnyObject]?, ErrorType?) -> Void)?) {
        callAPIAction("start", onVPS: VPSName, completionBlock: completionBlock)
    }
    
    /**
     Stop a VPS.
     */
    func stopVPSWithName(VPSName: String, completionBlock: (([String:AnyObject]?, ErrorType?) -> Void)?) {
        callAPIAction("stop", onVPS: VPSName, completionBlock: completionBlock)
    }
    
    
    // MARK: - Private methods
    
    /**
    Start the timers.
    */
    private func startTimers() {
        runningTasksTimer = NSTimer(fireDate: NSDate(timeIntervalSinceNow: runningTasksTimerTimeInterval), interval: runningTasksTimerTimeInterval, target: self, selector: Selector("refreshVPSTasks"), userInfo: nil, repeats: true)
        if let timer = runningTasksTimer {
            NSRunLoop.mainRunLoop().addTimer(timer, forMode: NSRunLoopCommonModes)
        }
        
        runningPropertiesTimer = NSTimer(fireDate: NSDate(timeIntervalSinceNow: runningTasksTimerTimeInterval), interval: runningTasksTimerTimeInterval, target: self, selector: Selector("refreshVPSProperties"), userInfo: nil, repeats: true)
        if let timer = runningPropertiesTimer {
            NSRunLoop.mainRunLoop().addTimer(timer, forMode: NSRunLoopCommonModes)
        }
    }
    
    /**
    Refresh the VPS.
    */
    @objc func refreshVPS() {
        loadVPSWithBlock(nil)
    }
    
    /**
     Refresh the VPS properties.
     */
    @objc func refreshVPSProperties() {
        for (VPSName, running) in runningProperties {
            if !running {
                reloadVPSPropertiesWithName(VPSName, completionBlock: nil)
            }
        }
    }
    
    /**
     Refresh the VPS tasks.
     */
    @objc func refreshVPSTasks() {
        for (VPSName, task) in runningTasks {
            if !task.running {
                reloadVPSTaskWithVPSName(VPSName, taskId: task.id, completionBlock: nil)
            }
        }
    }
    
    /**
     Call API: action on VPS
     */
    private func callAPIAction(action: String, onVPS VPSName: String, completionBlock: (([String:AnyObject]?, ErrorType?) -> Void)?) {
        // The VPS is flagged as waiting the result of an action.
        let context = self.coreDataController.newManagedObjectContext()
        context.performBlock({ () -> Void in
            do {
                let fetchRequest = NSFetchRequest(entityName: "OVHVPS")
                fetchRequest.predicate = NSPredicate(format: "%K = %@", "name", VPSName)
                fetchRequest.fetchLimit = 1
                
                let fetchedVPS = try context.executeFetchRequest(fetchRequest)
                if fetchedVPS.count > 0 {
                    let VPS = fetchedVPS.first as! OVHVPS
                    VPS.waitingTask = true
                }
            } catch let error {
                print("Failed to fetch VPS: \(error)")
            }
            
            self.coreDataController.saveManagedObjectContext(context)
        })
        
        // Launch the request.
        OVHAPI.post("/vps/\(VPSName)/\(action)") { (result, error, request, response) -> Void in
            
            // The process is run in the background to not block the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in
                
                // Defered actions: call the completion block.
                var completionVPSTask : [String:AnyObject]?
                var completionError: ErrorType?
                defer {
                    if let block = completionBlock {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            block(completionVPSTask, completionError)
                        })
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
                
                // Save the task.
                if let VPSTask = (result as? [String:AnyObject]) {
                    
                    let context = self.coreDataController.newManagedObjectContext()
                    context.performBlockAndWait({ () -> Void in
                        do {
                            let fetchRequest = NSFetchRequest(entityName: "OVHVPS")
                            fetchRequest.predicate = NSPredicate(format: "%K = %@", "name", VPSName)
                            fetchRequest.fetchLimit = 1
                            
                            let fetchedVPS = try context.executeFetchRequest(fetchRequest)
                            if fetchedVPS.count > 0 {
                                let VPSTaskEntity = NSEntityDescription.insertNewObjectForEntityForName("OVHVPSTask", inManagedObjectContext: context) as! OVHVPSTask
                                VPSTaskEntity.id = ((VPSTask["id"] as? NSNumber)?.longLongValue)!
                                VPSTaskEntity.type = VPSTask["type"] as? String
                                VPSTaskEntity.state = VPSTask["state"] as? String
                                VPSTaskEntity.progress = ((VPSTask["progress"] as? NSNumber)?.longLongValue)!
                                
                                let VPS = fetchedVPS.first as! OVHVPS
                                let oldWatchRepresentation = VPS.watchRepresentation()
                                
                                VPS.currentTask = VPSTaskEntity
                                VPS.waitingTask = false
                                
                                completionVPSTask = VPSTask
                                
                                self.runningTasks[VPSName] = RunningTask(id: VPSTaskEntity.id, running: false)
                                
                                // Send to the watch the updated state of VPS.
                                WatchSessionManager.sharedManager.updateVPS(VPS.watchRepresentation(), withOldRepresentation: oldWatchRepresentation)
                                WatchSessionManager.sharedManager.updateGlance()
                                WatchSessionManager.sharedManager.updateComplication()
                            }
                        } catch let error {
                            completionError = error
                            print("Failed to fetch VPS: \(error)")
                        }
                        
                        self.coreDataController.saveManagedObjectContext(context)
                    })
                }
            })
        }
    }
    
    
    // MARK: - WatchSessionManagerProtocol methods
    
    func APICredentials() -> [String : AnyObject] {
        var credentials = ["applicationKey": OVHAPI.applicationKey, "applicationSecret": OVHAPI.applicationSecret]
        
        if let consumerKey = OVHAPI.consumerKey {
            credentials["consumerKey"] = consumerKey
        }
        
        return credentials
    }
    
    func VPSList() -> [[String:AnyObject]] {
        var list = [[String:AnyObject]]()
        
        let context = coreDataController.newManagedObjectContext()
        context.performBlockAndWait { () -> Void in
            let fetchRequest = NSFetchRequest(entityName: "OVHVPS")
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "displayName", ascending: true)]
            
            do {
                let VPSList = try context.executeFetchRequest(fetchRequest) as! [OVHVPS]
                
                for VPS in VPSList {
                    list.append(VPS.watchRepresentation())
                }
            } catch let error {
                print("Can not fetch the VPS objects: \(error)")
            }
        }
        
        return list
    }
    
    func glanceData() -> [String:AnyObject] {
        var countOfRunningVPS = 0, countOfStoppedVPS = 0, countOfUnknownVPS = 0, countOfBusyVPS = 0
        
        let context = coreDataController.newManagedObjectContext()
        context.performBlockAndWait { () -> Void in
            var request: NSFetchRequest
            
            let predicateCurrentTaskIsNil = NSPredicate(format: "%K = nil", "currentTask")
            
            // Count of running VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            request.predicate = NSCompoundPredicate.init(andPredicateWithSubpredicates: [predicateCurrentTaskIsNil, NSPredicate(format: "%K = %@", "state", OVHVPSState.running.rawValue)])
            countOfRunningVPS = context.countForFetchRequest(request, error: nil)
            
            // Count of stopped VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            request.predicate = NSCompoundPredicate.init(andPredicateWithSubpredicates: [predicateCurrentTaskIsNil, NSPredicate(format: "%K = %@", "state", OVHVPSState.stopped.rawValue)])
            countOfStoppedVPS = context.countForFetchRequest(request, error: nil)
            
            // Count of unknown VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            request.predicate = NSCompoundPredicate.init(andPredicateWithSubpredicates: [predicateCurrentTaskIsNil, NSPredicate(format: "%K = %@", "state", OVHVPSState.unknown.rawValue)])
            countOfUnknownVPS = context.countForFetchRequest(request, error: nil)
            
            // Count of busy VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            let predicateCurrentTaskIsNotNil = NSPredicate(format: "%K != nil", "currentTask")
            let predicateStates = NSCompoundPredicate.init(andPredicateWithSubpredicates: [NSPredicate(format: "%K != %@", "state", OVHVPSState.unknown.rawValue), NSPredicate(format: "%K != %@", "state", OVHVPSState.stopped.rawValue), NSPredicate(format: "%K != %@", "state", OVHVPSState.running.rawValue)])
            request.predicate = NSCompoundPredicate.init(orPredicateWithSubpredicates: [predicateCurrentTaskIsNotNil, predicateStates])
            countOfBusyVPS = context.countForFetchRequest(request, error: nil)
        }
        
        return ["running": countOfRunningVPS, "stopped": countOfStoppedVPS, "unknown": countOfUnknownVPS, "busy": countOfBusyVPS]
    }
    
    func complicationData() -> [String:AnyObject] {
        var countOfVPS = 0, countOfUnknownVPS = 0, countOfBusyVPS = 0
        
        let context = coreDataController.newManagedObjectContext()
        context.performBlockAndWait { () -> Void in
            var request: NSFetchRequest
            
            // Count of VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            countOfVPS = context.countForFetchRequest(request, error: nil)
            
            // Count of unknown VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            request.predicate = NSCompoundPredicate.init(andPredicateWithSubpredicates: [NSPredicate(format: "%K = nil", "currentTask"), NSPredicate(format: "%K = %@", "state", OVHVPSState.unknown.rawValue)])
            countOfUnknownVPS = context.countForFetchRequest(request, error: nil)
            
            // Count of busy VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            let predicateCurrentTaskIsNotNil = NSPredicate(format: "%K != nil", "currentTask")
            let predicateStates = NSCompoundPredicate.init(andPredicateWithSubpredicates: [NSPredicate(format: "%K != %@", "state", OVHVPSState.unknown.rawValue), NSPredicate(format: "%K != %@", "state", OVHVPSState.stopped.rawValue), NSPredicate(format: "%K != %@", "state", OVHVPSState.running.rawValue)])
            request.predicate = NSCompoundPredicate.init(orPredicateWithSubpredicates: [predicateCurrentTaskIsNotNil, predicateStates])
            countOfBusyVPS = context.countForFetchRequest(request, error: nil)
        }
        
        return ["all": countOfVPS, "unknown": countOfUnknownVPS, "busy": countOfBusyVPS]
    }
    
    func loadNewVPSTask(VPSName: String, task: [String : AnyObject]) {
        let context = coreDataController.newManagedObjectContext()
        context.performBlockAndWait { () -> Void in
            do {
                let fetchRequest = NSFetchRequest(entityName: "OVHVPS")
                fetchRequest.predicate = NSPredicate(format: "%K = %@", "name", VPSName)
                fetchRequest.fetchLimit = 1
                
                let fetchedVPS = try context.executeFetchRequest(fetchRequest)
                if fetchedVPS.count > 0 {
                    let VPSTaskEntity = NSEntityDescription.insertNewObjectForEntityForName("OVHVPSTask", inManagedObjectContext: context) as! OVHVPSTask
                    VPSTaskEntity.id = ((task["id"] as? NSNumber)?.longLongValue)!
                    VPSTaskEntity.type = task["type"] as? String
                    VPSTaskEntity.state = task["state"] as? String
                    VPSTaskEntity.progress = ((task["progress"] as? NSNumber)?.longLongValue)!
                    
                    let VPS = fetchedVPS.first as! OVHVPS
                    VPS.currentTask = VPSTaskEntity
                    VPS.waitingTask = false
                    
                    self.coreDataController.saveManagedObjectContext(context)
                    
                    self.reloadVPSTaskWithVPSName(VPSName, taskId: VPSTaskEntity.id, completionBlock: nil)
                }
            } catch let error {
                print("Failed to fetch VPS: \(error)")
            }
        }
    }
    
    
    // MARK: - Lifecycle
    
    init() {
        if let credentials = NSDictionary(contentsOfFile: NSBundle.mainBundle().pathForResource("Credentials", ofType: "plist")!) {
            OVHAPI = OVHAPIWrapper(endpoint: .OVHEU, applicationKey: credentials["ApplicationKey"] as! String, applicationSecret: credentials["ApplicationSecret"] as! String, consumerKey: credentials["ConsumerKey"] as? String)
            OVHAPI.enableLogs = true
        } else {
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            print("Can not init the OVH API wrapper, please check your Credentials.plist file.")
            abort()
        }
        
        startTimers()
        
        WatchSessionManager.sharedManager.delegate = self
    }
    
}
