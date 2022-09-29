//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 29.09.2022.
//

import Foundation
import CoreData

class CWCoreDataManager: NSPersistentContainer {
    
    init() {
        guard
            let objectModelURL = Bundle.module.url(forResource: "CWData", withExtension: "momd"),
            let objectModel = NSManagedObjectModel(contentsOf: objectModelURL)
        else {
            fatalError("Failed to retrieve the object model")
        }
        super.init(name: "CWData", managedObjectModel: objectModel)
        self.initialize()
    }
    
    private func initialize() {
        self.loadPersistentStores { description, error in
            if let err = error {
                fatalError("Failed to load CoreData: \(err)")
            }
        }
    }
    
    func user() throws -> CWDUser {
        let fetchRequest = NSFetchRequest<CWDUser>(entityName: "CWDUser")
        guard let user = try self.viewContext.fetch(fetchRequest).first else {
            return NSEntityDescription.insertNewObject(forEntityName: "CWDUser", into: self.viewContext) as! CWDUser
        }
        
        return user
    }
    
    func save() throws {
        if self.viewContext.hasChanges {
            do {
                try self.viewContext.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
}
