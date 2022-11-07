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
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "CWData")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()
    
    func user() throws -> CWDUser {
        let fetchRequest = NSFetchRequest<CWDUser>(entityName: "CWDUser")
        guard let user = try self.viewContext.fetch(fetchRequest).first else {
            return NSEntityDescription.insertNewObject(forEntityName: "CWDUser", into: self.viewContext) as! CWDUser
        }
        
        return user
    }
    
    func addresses() throws -> [CWDAddress] {
        let fetchRequest = NSFetchRequest<CWDAddress>(entityName: "CWDAddress")
        let sort = NSSortDescriptor(key: #keyPath(CWDAddress.updatedAt), ascending: false)
        fetchRequest.sortDescriptors = [sort]
        
        return try self.viewContext.fetch(fetchRequest) as [CWDAddress]
    }
    
    func newAddress() -> CWDAddress {
        return NSEntityDescription.insertNewObject(forEntityName: "CWDAddress", into: self.viewContext) as! CWDAddress
    }
    
    func deleteAddress(id: UUID) throws {
        let fetchRequest = NSFetchRequest<CWDAddress>(entityName: "CWDAddress")
        fetchRequest.predicate = NSPredicate(format: "id = %@", id.uuidString)
        
        guard let address = try self.viewContext.fetch(fetchRequest).first else { return }
        
        self.viewContext.delete(address)
        try self.save()
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
