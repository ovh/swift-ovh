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
    
    fileprivate struct RunningTask {
        let id: Int64
        let running: Bool
    }
    
    
    // MARK: - Properties
    
    // The OVH API wrapper, used to manage the calls to the API.
    let OVHAPI: OVHAPIWrapper
    
    // Manage the CoreData layer.
    fileprivate let coreDataController = CoreDataManager.sharedManager
    
    // The running tasks are tracked to be refreshed.
    fileprivate var runningTasks = [String:RunningTask]()
    fileprivate var runningTasksTimer: Timer?
    fileprivate let runningTasksTimerTimeInterval: TimeInterval = 15
    
    // The properties (state) of the VPS are tracked to be refreshed.
    fileprivate var runningProperties = [String:Bool]()
    fileprivate var runningPropertiesTimer: Timer?
    fileprivate let runningPropertiesTimerTimeInterval: TimeInterval = 15
    
    // The VPS are refreshed every hour.
    fileprivate var runningVPSTimer: Timer?
    fileprivate let runningVPSTimerTimeInterval: TimeInterval = 60*60
    
    
    // MARK: - Data loading
    
    /**
    Load all the VPS from the OVH API.
    */
    func loadVPS(withBlock completionBlock: ((Error?) -> Void)? = nil) {
        // Invalidate the current timer.
        if let timer = runningVPSTimer {
            timer.invalidate()
        }
        
        // Launch the request.
        OVHAPI.get("/vps") { (result, error, request, response) -> Void in
            
            // The process is run in the background to not block the main thread.
            DispatchQueue.global(qos: .background).async {
                // Defered actions: call the completion block.
                var completionError: Error?
                defer {
                    if let block = completionBlock {
                        DispatchQueue.main.async {
                            block(completionError)
                        }
                    }
                    
                    // Start the timer.
                    var fireDateTimeInterval = self.runningVPSTimerTimeInterval
                    if let _ = completionError {
                        fireDateTimeInterval = 30
                    }
                    self.runningVPSTimer = Timer(fireAt: Date(timeIntervalSinceNow: fireDateTimeInterval), interval: self.runningTasksTimerTimeInterval, target: self, selector: #selector(OVHVPSController.refreshVPS), userInfo: nil, repeats: false)
                    if let timer = self.runningVPSTimer {
                        RunLoop.main.add(timer, forMode: RunLoopMode.commonModes)
                    }
                }
                
                // Handle the error.
                guard error == nil else {
                    completionError = error
                    return
                }
                
                // Handle invalid response.
                guard result is [String] else {
                    completionError = OVHAPIError.invalidRequestResponse
                    return
                }
                
                // Handle the VPS: save them and load the properties.
                if let allVPS = (result as? [String]) {
                    
                    let context = self.coreDataController.newManagedObjectContext()
                    context.performAndWait({
                        do {
                            // Get all the saved VPS.
                            let fetchRequest: NSFetchRequest<OVHVPS> = OVHVPS.fetchRequest()
                            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
                            fetchRequest.includesSubentities = false
                            fetchRequest.propertiesToFetch = ["name"]
                            
                            var fetchedVPS = try context.fetch(fetchRequest)
                            
                            for VPS in allVPS {
                                let VPSName = VPS as String
                                
                                // Is this VPS already saved?
                                var found = false
                                if fetchedVPS.count > 0 {
                                    for i in 0...fetchedVPS.count {
                                        if fetchedVPS[i].name == VPSName {
                                            found = true
                                            fetchedVPS.remove(at: i)
                                            break
                                        }
                                    }
                                }
                                
                                // If not saved create it.
                                if !found {
                                    let VPSEntity = NSEntityDescription.insertNewObject(forEntityName: "OVHVPS", into: context) as! OVHVPS
                                    VPSEntity.name = VPSName
                                    VPSEntity.displayName = VPSName
                                    VPSEntity.state = OVHVPSState.unknown.rawValue
                                    
                                    self.coreDataController.saveManagedObjectContext(context)
                                    
                                    // Load the properties.
                                    self.reloadVPSProperties(withName: VPSName) { properties, error in
                                        if let properties = properties, let state = properties["state"] as? String {
                                            if state != OVHVPSState.running.rawValue && state != OVHVPSState.stopped.rawValue {
                                                self.loadVPSTask(withVPSName: VPSName)
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Delete the VPS that are not returned by the request.
                            for VPS in fetchedVPS {
                                context.delete(VPS)
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
            }
        }
    }
    
    /**
     Load the properties of a VPS from the OVH API.
     */
    func reloadVPSProperties(withName VPSName: String, andCompletionBlock completionBlock: (([String:AnyObject]?, Error?) -> Void)? = nil) {
        // Track this running task.
        runningProperties[VPSName] = true
        
        // Launch the request.
        OVHAPI.get("/vps/\(VPSName)") { (result, error, request, response) -> Void in
            
            // The process is run in the background to not block the main thread.
            DispatchQueue.global(qos: .background).async {
                
                // Defered actions: call the completion block.
                var completionProperties : [String:AnyObject]?
                var completionError: Error?
                defer {
                    if let block = completionBlock {
                        DispatchQueue.main.async {
                            block(completionProperties, completionError)
                        }
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
                    completionError = OVHAPIError.invalidRequestResponse
                    return
                }
                
                // Save the properties.
                if let VPSProperties = (result as? [String:AnyObject]) {
                    
                    let context = self.coreDataController.newManagedObjectContext()
                    context.performAndWait({
                        var keepTrackingTask = false
                        
                        do {
                            let fetchRequest: NSFetchRequest<OVHVPS> = OVHVPS.fetchRequest()
                            fetchRequest.predicate = NSPredicate(format: "%K = %@", "name", VPSName)
                            fetchRequest.fetchLimit = 1
                            
                            let fetchedVPS = try context.fetch(fetchRequest)
                            if let VPS = fetchedVPS.first {
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
                            self.runningProperties.removeValue(forKey: VPSName)
                        }
                        
                        self.coreDataController.saveManagedObjectContext(context)
                    })
                }
            }
        }
    }
    
    /**
     Load the tasks of a VPS from the OVH API.
     */
    func loadVPSTask(withVPSName VPSName: String, andCompletionBlock completionBlock: (([String:AnyObject]?, Error?) -> Void)? = nil) {
        // Launch the request.
        OVHAPI.get("/vps/\(VPSName)/tasks") { (result, error, request, response) -> Void in
            
            // The process is run in the background to not block the main thread.
            DispatchQueue.global(qos: .background).async {
                
                // Defered actions: call the completion block.
                var completionVPSTask: [String:AnyObject]?
                var completionError: Error?
                defer {
                    if let block = completionBlock {
                        DispatchQueue.main.async {
                            block(completionVPSTask, completionError)
                        }
                    }
                }
                
                // Handle the error.
                guard error == nil else {
                    completionError = error
                    return
                }
                
                // Handle invalid response.
                guard result is [String] else {
                    completionError = OVHAPIError.invalidRequestResponse
                    return
                }
                
                // Save the properties.
                if let VPSTaskIDs = (result as? [String]) {
                    if VPSTaskIDs.count > 0 {
                        if let VPSTaskIDObject = VPSTaskIDs.first, let VPSTaskID = Int64(VPSTaskIDObject) {
                            
                            // As we have a defer block and the following API call is asynchronous,
                            // a semaphore is used in order to wait to not return now.
                            let semaphore = DispatchSemaphore(value: 0)
                            
                            self.reloadVPSTask(withVPSName: VPSName, taskId: VPSTaskID, andCompletionBlock: { (VPSTask, error) in
                                completionVPSTask = VPSTask
                                completionError = error
                                semaphore.signal()
                            })
                            
                            // Waiting for the end of call "/vps/x/task/y"
                            let _ = semaphore.wait(timeout: DispatchTime.distantFuture)
                        }
                    }
                }
            }
        }
    }
    
    /**
     Load the task with ID of a VPS from the OVH API.
     */
    func reloadVPSTask(withVPSName VPSName: String, taskId: Int64, andCompletionBlock completionBlock: (([String:AnyObject]?, Error?) -> Void)? = nil) {
        // Track this running task.
        runningTasks[VPSName] = RunningTask(id: taskId, running: true)
        
        // Launch the request.
        self.OVHAPI.get("/vps/\(VPSName)/tasks/\(taskId)") { (result, error, request, response) -> Void in
            
            // The process is running in the background to not block the main thread.
            DispatchQueue.global(qos: .background).async {
                
                // Defered actions: call the completion block.
                var completionVPSTask: [String:AnyObject]?
                var completionError: Error?
                defer {
                    if let block = completionBlock {
                        DispatchQueue.main.async {
                            block(completionVPSTask, completionError)
                        }
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
                    completionError = OVHAPIError.invalidRequestResponse
                    return
                }
                
                // Save the task.
                if let VPSTask = (result as? [String:AnyObject]) {
                    
                    let context = self.coreDataController.newManagedObjectContext()
                    context.performAndWait({
                        var keepTrackingTask = false
                        
                        do {
                            let fetchRequest: NSFetchRequest<OVHVPS> = OVHVPS.fetchRequest()
                            fetchRequest.predicate = NSPredicate(format: "%K = %@", "name", VPSName)
                            fetchRequest.fetchLimit = 1
                            
                            let fetchedVPS = try context.fetch(fetchRequest)
                            if let VPS = fetchedVPS.first {
                                let VPSTaskId = VPSTask["id"] as? NSNumber
                                let VPSTaskProgress = VPSTask["progress"] as? NSNumber
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
                                    let VPSTaskEntity = NSEntityDescription.insertNewObject(forEntityName: "OVHVPSTask", into: context) as! OVHVPSTask
                                    VPSTaskEntity.id = VPSTaskId
                                    VPSTaskEntity.type = VPSTaskType
                                    VPSTaskEntity.state = VPSTaskState
                                    VPSTaskEntity.progress = VPSTaskProgress
                                    
                                    VPS.currentTask = VPSTaskEntity
                                }
                                
                                if let task = VPS.currentTask {
                                    if task.isFinished() {
                                        VPS.currentTask = nil
                                        
                                        self.reloadVPSProperties(withName: VPSName)
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
                            self.runningTasks.removeValue(forKey: VPSName)
                        }
                        
                        self.coreDataController.saveManagedObjectContext(context)
                    })
                }
            }
        }
    }
    
    /**
     Reboot a VPS.
     */
    func rebootVPS(withName VPSName: String, andCompletionBlock completionBlock: (([String:AnyObject]?, Error?) -> Void)? = nil) {
        call(APIAction: "reboot", onVPS: VPSName, withCompletionBlock: completionBlock)
    }
    
    /**
     Start a VPS.
     */
    func startVPS(withName VPSName: String, andCompletionBlock completionBlock: (([String:AnyObject]?, Error?) -> Void)? = nil) {
        call(APIAction: "start", onVPS: VPSName, withCompletionBlock: completionBlock)
    }
    
    /**
     Stop a VPS.
     */
    func stopVPS(withName VPSName: String, andCompletionBlock completionBlock: (([String:AnyObject]?, Error?) -> Void)? = nil) {
        call(APIAction: "stop", onVPS: VPSName, withCompletionBlock: completionBlock)
    }
    
    
    // MARK: - Private methods
    
    /**
    Start the timers.
    */
    fileprivate func startTimers() {
        runningTasksTimer = Timer(fireAt: Date(timeIntervalSinceNow: runningTasksTimerTimeInterval), interval: runningTasksTimerTimeInterval, target: self, selector: #selector(OVHVPSController.refreshVPSTasks), userInfo: nil, repeats: true)
        if let timer = runningTasksTimer {
            RunLoop.main.add(timer, forMode: RunLoopMode.commonModes)
        }
        
        runningPropertiesTimer = Timer(fireAt: Date(timeIntervalSinceNow: runningTasksTimerTimeInterval), interval: runningTasksTimerTimeInterval, target: self, selector: #selector(OVHVPSController.refreshVPSProperties), userInfo: nil, repeats: true)
        if let timer = runningPropertiesTimer {
            RunLoop.main.add(timer, forMode: RunLoopMode.commonModes)
        }
    }
    
    /**
    Refresh the VPS.
    */
    @objc func refreshVPS() {
        loadVPS()
    }
    
    /**
     Refresh the VPS properties.
     */
    @objc func refreshVPSProperties() {
        for (VPSName, running) in runningProperties {
            if !running {
                reloadVPSProperties(withName: VPSName)
            }
        }
    }
    
    /**
     Refresh the VPS tasks.
     */
    @objc func refreshVPSTasks() {
        for (VPSName, task) in runningTasks {
            if !task.running {
                reloadVPSTask(withVPSName: VPSName, taskId: task.id)
            }
        }
    }
    
    /**
     Call API: action on VPS
     */
    fileprivate func call(APIAction action: String, onVPS VPSName: String, withCompletionBlock completionBlock: (([String:AnyObject]?, Error?) -> Void)?) {
        // The VPS is flagged as waiting the result of an action.
        let context = self.coreDataController.newManagedObjectContext()
        context.perform({ () -> Void in
            do {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "OVHVPS")
                fetchRequest.predicate = NSPredicate(format: "%K = %@", "name", VPSName)
                fetchRequest.fetchLimit = 1
                
                let fetchedVPS = try context.fetch(fetchRequest)
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
            DispatchQueue.global(qos: .background).async {
                // Defered actions: call the completion block.
                var completionVPSTask : [String:AnyObject]?
                var completionError: Error?
                defer {
                    if let block = completionBlock {
                        DispatchQueue.main.async {
                            block(completionVPSTask, completionError)
                        }
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
                
                // Save the task.
                if let VPSTask = (result as? [String:AnyObject]) {
                    
                    let context = self.coreDataController.newManagedObjectContext()
                    context.performAndWait({
                        do {
                            let fetchRequest: NSFetchRequest<OVHVPS> = OVHVPS.fetchRequest()
                            fetchRequest.predicate = NSPredicate(format: "%K = %@", "name", VPSName)
                            fetchRequest.fetchLimit = 1
                            
                            let fetchedVPS = try context.fetch(fetchRequest)
                            if let VPS = fetchedVPS.first {
                                let VPSTaskEntity = NSEntityDescription.insertNewObject(forEntityName: "OVHVPSTask", into: context) as! OVHVPSTask
                                VPSTaskEntity.id = VPSTask["id"] as? NSNumber
                                VPSTaskEntity.type = VPSTask["type"] as? String
                                VPSTaskEntity.state = VPSTask["state"] as? String
                                VPSTaskEntity.progress = VPSTask["progress"] as? NSNumber
                                
                                let oldWatchRepresentation = VPS.watchRepresentation()
                                
                                VPS.currentTask = VPSTaskEntity
                                VPS.waitingTask = false
                                
                                completionVPSTask = VPSTask
                                
                                if let taskId = VPSTaskEntity.id?.int64Value {
                                    self.runningTasks[VPSName] = RunningTask(id: taskId, running: false)
                                }
                                
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
            }
        }
    }
    
    
    // MARK: - WatchSessionManagerProtocol methods
    
    func APICredentials() -> [String : AnyObject] {
        var credentials = ["applicationKey": OVHAPI.applicationKey, "applicationSecret": OVHAPI.applicationSecret]
        
        if let consumerKey = OVHAPI.consumerKey {
            credentials["consumerKey"] = consumerKey
        }
        
        return credentials as [String : AnyObject]
    }
    
    func VPSList() -> [[String:AnyObject]] {
        var list = [[String:AnyObject]]()
        
        let context = coreDataController.newManagedObjectContext()
        context.performAndWait { () -> Void in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "OVHVPS")
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "displayName", ascending: true)]
            
            do {
                let VPSList = try context.fetch(fetchRequest) as! [OVHVPS]
                
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
        context.performAndWait { () -> Void in
            var request: NSFetchRequest<NSFetchRequestResult>
            
            let predicateCurrentTaskIsNil = NSPredicate(format: "%K = nil", "currentTask")
            
            // Count of running VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            request.predicate = NSCompoundPredicate.init(andPredicateWithSubpredicates: [predicateCurrentTaskIsNil, NSPredicate(format: "%K = %@", "state", OVHVPSState.running.rawValue)])
            
            do {
                countOfRunningVPS = try context.count(for: request)
            }
            catch let e {
                debugPrint("Can not get the count of running VPS: \(e)")
            }
            
            // Count of stopped VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            request.predicate = NSCompoundPredicate.init(andPredicateWithSubpredicates: [predicateCurrentTaskIsNil, NSPredicate(format: "%K = %@", "state", OVHVPSState.stopped.rawValue)])
            
            do {
                countOfStoppedVPS = try context.count(for: request)
            }
            catch let e {
                debugPrint("Can not get the count of stopped VPS: \(e)")
            }
            
            // Count of unknown VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            request.predicate = NSCompoundPredicate.init(andPredicateWithSubpredicates: [predicateCurrentTaskIsNil, NSPredicate(format: "%K = %@", "state", OVHVPSState.unknown.rawValue)])
            
            do {
                countOfUnknownVPS = try context.count(for: request)
            }
            catch let e {
                debugPrint("Can not get the count of unknown VPS: \(e)")
            }
            
            // Count of busy VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            let predicateCurrentTaskIsNotNil = NSPredicate(format: "%K != nil", "currentTask")
            let predicateStates = NSCompoundPredicate.init(andPredicateWithSubpredicates: [NSPredicate(format: "%K != %@", "state", OVHVPSState.unknown.rawValue), NSPredicate(format: "%K != %@", "state", OVHVPSState.stopped.rawValue), NSPredicate(format: "%K != %@", "state", OVHVPSState.running.rawValue)])
            request.predicate = NSCompoundPredicate.init(orPredicateWithSubpredicates: [predicateCurrentTaskIsNotNil, predicateStates])
            
            do {
                countOfBusyVPS = try context.count(for: request)
            }
            catch let e {
                debugPrint("Can not get the count of busy VPS: \(e)")
            }
        }
        
        return ["running": countOfRunningVPS as AnyObject, "stopped": countOfStoppedVPS as AnyObject, "unknown": countOfUnknownVPS as AnyObject, "busy": countOfBusyVPS as AnyObject]
    }
    
    func complicationData() -> [String:AnyObject] {
        var countOfVPS = 0, countOfUnknownVPS = 0, countOfBusyVPS = 0
        
        let context = coreDataController.newManagedObjectContext()
        context.performAndWait { () -> Void in
            var request: NSFetchRequest<NSFetchRequestResult>
            
            // Count of VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            do {
                countOfVPS = try context.count(for: request)
            }
            catch let e {
                debugPrint("Can not get the count of VPS: \(e)")
            }
            
            // Count of unknown VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            request.predicate = NSCompoundPredicate.init(andPredicateWithSubpredicates: [NSPredicate(format: "%K = nil", "currentTask"), NSPredicate(format: "%K = %@", "state", OVHVPSState.unknown.rawValue)])
            do {
                countOfUnknownVPS = try context.count(for: request)
            }
            catch let e {
                debugPrint("Can not get the count of unknown VPS: \(e)")
            }
            
            // Count of busy VPS.
            request = NSFetchRequest(entityName: "OVHVPS")
            let predicateCurrentTaskIsNotNil = NSPredicate(format: "%K != nil", "currentTask")
            let predicateStates = NSCompoundPredicate.init(andPredicateWithSubpredicates: [NSPredicate(format: "%K != %@", "state", OVHVPSState.unknown.rawValue), NSPredicate(format: "%K != %@", "state", OVHVPSState.stopped.rawValue), NSPredicate(format: "%K != %@", "state", OVHVPSState.running.rawValue)])
            request.predicate = NSCompoundPredicate.init(orPredicateWithSubpredicates: [predicateCurrentTaskIsNotNil, predicateStates])
            do {
                countOfBusyVPS = try context.count(for: request)
            }
            catch let e {
                debugPrint("Can not get the count of busy VPS: \(e)")
            }
        }
        
        return ["all": countOfVPS as AnyObject, "unknown": countOfUnknownVPS as AnyObject, "busy": countOfBusyVPS as AnyObject]
    }
    
    func loadNewVPSTask(_ VPSName: String, task: [String : AnyObject]) {
        let context = coreDataController.newManagedObjectContext()
        context.performAndWait { () -> Void in
            do {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "OVHVPS")
                fetchRequest.predicate = NSPredicate(format: "%K = %@", "name", VPSName)
                fetchRequest.fetchLimit = 1
                
                let fetchedVPS = try context.fetch(fetchRequest)
                if fetchedVPS.count > 0 {
                    let VPSTaskEntity = NSEntityDescription.insertNewObject(forEntityName: "OVHVPSTask", into: context) as! OVHVPSTask
                    VPSTaskEntity.id = task["id"] as? NSNumber
                    VPSTaskEntity.type = task["type"] as? String
                    VPSTaskEntity.state = task["state"] as? String
                    VPSTaskEntity.progress = task["progress"] as? NSNumber
                    
                    let VPS = fetchedVPS.first as! OVHVPS
                    VPS.currentTask = VPSTaskEntity
                    VPS.waitingTask = false
                    
                    self.coreDataController.saveManagedObjectContext(context)
                    
                    self.reloadVPSTask(withVPSName: VPSName, taskId: VPSTaskEntity.id as! Int64)
                }
            } catch let error {
                print("Failed to fetch VPS: \(error)")
            }
        }
    }
    
    
    // MARK: - Lifecycle
    
    init() {
        if let credentials = NSDictionary(contentsOfFile: Bundle.main.path(forResource: "Credentials", ofType: "plist")!) {
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
