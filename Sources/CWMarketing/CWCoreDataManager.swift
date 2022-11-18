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
    
    // MARK: - User
    
    func user() throws -> CWDUser {
        let fetchRequest = NSFetchRequest<CWDUser>(entityName: "CWDUser")
        guard let user = try self.viewContext.fetch(fetchRequest).first else {
            return NSEntityDescription.insertNewObject(forEntityName: "CWDUser", into: self.viewContext) as! CWDUser
        }
        
        return user
    }
    
    func deleteUser() throws {
        let fetchRequest = NSFetchRequest<CWDUser>(entityName: "CWDUser")
        
        guard let user = try self.viewContext.fetch(fetchRequest).first else { return }
        
        self.viewContext.delete(user)
        try self.save()
    }
    
    // MARK: - Concepts
    
    func concepts() throws -> [CWDConcept] {
        let fetchRequest = NSFetchRequest<CWDConcept>(entityName: "CWDConcept")
        let sort = NSSortDescriptor(key: #keyPath(CWDConcept.order), ascending: true)
        fetchRequest.sortDescriptors = [sort]
        fetchRequest.returnsObjectsAsFaults = false
        
        return try self.viewContext.fetch(fetchRequest) as [CWDConcept]
    }
    
    func conceptBy(id: String) throws -> CWDConcept? {
        let fetchRequest = NSFetchRequest<CWDConcept>(entityName: "CWDConcept")
        fetchRequest.predicate = NSPredicate(format: "externalId = %@", id)

        return try self.viewContext.fetch(fetchRequest).first
    }
    
    func newConcept() -> CWDConcept {
        return NSEntityDescription.insertNewObject(forEntityName: "CWDConcept", into: self.viewContext) as! CWDConcept
    }
    
    func deleteConcept(id: String) throws {
        let fetchRequest = NSFetchRequest<CWDAddress>(entityName: "CWDConcept")
        fetchRequest.predicate = NSPredicate(format: "id = %@", id)
        
        guard let concept = try self.viewContext.fetch(fetchRequest).first else { return }
        
        self.viewContext.delete(concept)
    }
    
    // MARK: - Terminals
    func terminals() throws -> [CWDTerminal] {
        let fetchRequest = NSFetchRequest<CWDTerminal>(entityName: "CWDTerminal")
        fetchRequest.returnsObjectsAsFaults = false
        let sort = NSSortDescriptor(key: #keyPath(CWDTerminal.order), ascending: true)
        fetchRequest.sortDescriptors = [sort]
        
        return try self.viewContext.fetch(fetchRequest) as [CWDTerminal]
    }
    
    func terminalsBy(concept id: String) throws -> [CWDTerminal] {
        let fetchRequest = NSFetchRequest<CWDTerminal>(entityName: "CWDTerminal")
        fetchRequest.predicate = NSPredicate(format: "conceptId = %@", id)
        fetchRequest.returnsObjectsAsFaults = false
        let sort = NSSortDescriptor(key: #keyPath(CWDTerminal.order), ascending: true)
        fetchRequest.sortDescriptors = [sort]
        
        return try self.viewContext.fetch(fetchRequest) as [CWDTerminal]
    }
    
    func terminalBy(id: String) throws -> CWDTerminal? {
        let fetchRequest = NSFetchRequest<CWDTerminal>(entityName: "CWDTerminal")
        fetchRequest.predicate = NSPredicate(format: "externalId = %@", id)

        return try self.viewContext.fetch(fetchRequest).first
    }
    
    func newTerminal() -> CWDTerminal {
        return NSEntityDescription.insertNewObject(forEntityName: "CWDTerminal", into: self.viewContext) as! CWDTerminal
    }
    
    func deleteTerminal(id: String) throws {
        let fetchRequest = NSFetchRequest<CWDTerminal>(entityName: "CWDTerminal")
        fetchRequest.predicate = NSPredicate(format: "id = %@", id)
        
        guard let terminal = try self.viewContext.fetch(fetchRequest).first else { return }
        
        self.viewContext.delete(terminal)
    }
    
    // MARK: - PaymentTypes
    
    func paymentTypesBy(concept id: String) throws -> [CWDPaymentType] {
        let fetchRequest = NSFetchRequest<CWDPaymentType>(entityName: "CWDPaymentType")
        fetchRequest.predicate = NSPredicate(format: "conceptId = %@", id)
        
        return try self.viewContext.fetch(fetchRequest) as [CWDPaymentType]
    }
    
    func paymentTypeBy(id: String) throws -> CWDPaymentType? {
        let fetchRequest = NSFetchRequest<CWDPaymentType>(entityName: "CWDPaymentType")
        fetchRequest.predicate = NSPredicate(format: "externalId = %@", id)

        return try self.viewContext.fetch(fetchRequest).first
    }
    
    func newPaymentType() -> CWDPaymentType {
        return NSEntityDescription.insertNewObject(forEntityName: "CWDPaymentType", into: self.viewContext) as! CWDPaymentType
    }
    
    func deletePaymentType(id: String) throws {
        let fetchRequest = NSFetchRequest<CWDPaymentType>(entityName: "CWDPaymentType")
        fetchRequest.predicate = NSPredicate(format: "externalId = %@", id)
        
        guard let paymentType = try self.viewContext.fetch(fetchRequest).first else { return }
        
        self.viewContext.delete(paymentType)
    }
    
    // MARK: - DeliveryTypes
    
    func deliveryTypesBy(concept id: String) throws -> [CWDDeliveryType] {
        let fetchRequest = NSFetchRequest<CWDDeliveryType>(entityName: "CWDDeliveryType")
        fetchRequest.predicate = NSPredicate(format: "conceptId = %@", id)
        
        return try self.viewContext.fetch(fetchRequest) as [CWDDeliveryType]
    }
    
    func deliveryTypesBy(id: String) throws -> CWDDeliveryType? {
        let fetchRequest = NSFetchRequest<CWDDeliveryType>(entityName: "CWDDeliveryType")
        fetchRequest.predicate = NSPredicate(format: "externalId = %@", id)

        return try self.viewContext.fetch(fetchRequest).first
    }
    
    func newDeliveryType() -> CWDDeliveryType {
        return NSEntityDescription.insertNewObject(forEntityName: "CWDDeliveryType", into: self.viewContext) as! CWDDeliveryType
    }
    
    func deleteDeliveryType(id: String) throws {
        let fetchRequest = NSFetchRequest<CWDDeliveryType>(entityName: "CWDDeliveryType")
        fetchRequest.predicate = NSPredicate(format: "externalId = %@", id)
        
        guard let deliveryType = try self.viewContext.fetch(fetchRequest).first else { return }
        
        self.viewContext.delete(deliveryType)
    }
    
    // MARK: - Addresses
    
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
