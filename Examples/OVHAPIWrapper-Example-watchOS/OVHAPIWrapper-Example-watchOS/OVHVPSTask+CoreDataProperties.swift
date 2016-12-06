//
//  OVHVPSTask+CoreDataProperties.swift
//  OVHAPIWrapper-Example-watchOS
//
//  Created by Cyril on 06/12/2016.
//  Copyright © 2016 OVH SAS. All rights reserved.
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension OVHVPSTask {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OVHVPSTask> {
        return NSFetchRequest<OVHVPSTask>(entityName: "OVHVPSTask");
    }

    @NSManaged public var id: NSNumber?
    @NSManaged public var progress: NSNumber?
    @NSManaged public var state: String?
    @NSManaged public var type: String?
    @NSManaged public var currentVPSTask: OVHVPS?

}
