//
//  OVHVPS+CoreDataProperties.swift
//  OVHAPIWrapper-Example-watchOS
//
//  Created by Cyril on 06/12/2016.
//  Copyright © 2016 OVH SAS. All rights reserved.
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension OVHVPS {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<OVHVPS> {
        return NSFetchRequest<OVHVPS>(entityName: "OVHVPS");
    }

    @NSManaged public var displayName: String?
    @NSManaged public var name: String?
    @NSManaged public var offerType: String?
    @NSManaged public var state: String?
    @NSManaged public var waitingTask: NSNumber?
    @NSManaged public var currentTask: OVHVPSTask?

}
