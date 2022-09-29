//
//  CWMarketing.swift
//
//
//  Created by Clockwork, LLC on 20.09.2022.
//

import Foundation
import Alamofire
import AlamofireImage
import UIKit
import CryptoKit
import os.log
import CoreData

let version = "0.0.4"
let uri = "https://customer.api.cw.marketing"

public final class CW {
    
    public static var shared: CW = {
        let instance = CW()
        return instance
    }()
    
    private var headers = HTTPHeaders()
    private var config = CWConfig()
    private var imageCache: ImageRequestCache?
    private var downloader: ImageDownloader?
    private let queue = DispatchQueue(label: "marketing.cw.queue", attributes: .concurrent)
    private var cart: [String: [CWProduct]] = [:]
    private var token: String = "" {
        didSet {
            headers.add(name: "Authorization", value: "Bearer: \(token)")
//            updateToken(token: token)
        }
    }
    
    weak var delegate: CWDelegate?
    var delegates: [CWDelegate] = []
    
    /// Creates an instance from a config.
    ///
    public init() {
        let applicationDocumentsDirectory: URL = {
            let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            return urls[urls.count-1]
        }()
        
        os_log("coreData dir: %@", type: .info, applicationDocumentsDirectory.description)
    }
    
    /// Set config.
    ///
    /// - Parameters:
    ///   - config: Should contain `Company-Access-Key` and `Loyalaty-Id`.
    public func setConfig(config: CWConfig) {
        self.config = config
        headers.add(name: "Company-Access-Key", value: config.apiKey)
        headers.add(name: "Loyalaty-Id", value: config.loyaltyId)
        
        if let cacheRules = config.cacheRules {
            imageCache = AutoPurgingImageCache(memoryCapacity: cacheRules.memoryCapacity, preferredMemoryUsageAfterPurge: cacheRules.usageAfterPurge)
            let diskCache = URLCache(memoryCapacity: 0, diskCapacity: cacheRules.diskCapacity, diskPath: "marketing.cw.disk_cache")
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = diskCache
            downloader = ImageDownloader(configuration: configuration, imageCache: imageCache)
        }
    }
    
    // MARK: - Auth
    public func auth(phone: String, code: String, completion: @escaping(CWAuthResponse?, NSError?) -> Void) {
        let params = CWAuthRequest(phone: parsePhone(phone: phone), code: code)
        
        AF.request("\(uri)/auth/v1/token", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWAuthResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let token = val.access_token {
                        self.token = token
                    }
                    completion(val, nil)
                case .failure(let err):
                    completion(nil, err as NSError)
                }
            }
    }
    
    public func signup() {
        
    }
    
    public func requestCode(phone: String, completion: @escaping(CWCodeReponse?, NSError?) -> Void) {
        let params = CWAuthRequest(phone: parsePhone(phone: phone))
        
        AF.request("\(uri)/auth/v1/code", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWCodeReponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    completion(val, nil)
                case .failure(let err):
                    completion(nil, err as NSError)
                }
            }
    }
    
    // MARK: - Cart
    public func getCart(concept: CWConcept) -> [CWProduct] {
        var cart: [CWProduct] = []
        queue.sync {
            if let unwrappedCart = self.cart[concept._id] {
                cart = unwrappedCart
            }
        }
        return cart
    }
    
    public func wipeCart(concept: CWConcept) {
        self.cart = [:]
        delegates.forEach { delegate in
            delegate.wipeCart()
            delegate.totalDidUpdate(total: 0.0)
        }
    }
    
    public func addToCart(product: CWProduct, modifiers: [CWModifier] = [], amount: Float = 1.0) {
        let conceptId = product.conceptId
        var p = product
        
        queue.async(flags: .barrier) {
            guard var cart = self.cart[conceptId] else { return }
            if let index = cart.firstIndex(where: { $0.productHash == self.productHash(product: p, modifiers: modifiers) }) {
                if var count = cart[index].count {
                    count += amount
                }
            } else {
                p.count = amount
                p.orderModifiers = modifiers
                p.productHash = self.productHash(product: product, modifiers: modifiers)
                cart.append(p)
            }
        }
        
        delegates.forEach { delegate in
            delegate.addToCart(product: p)
            delegate.totalDidUpdate(total: self.getTotal(conceptId: conceptId))
        }
    }
    
    public func removeEntireFromCart(product: CWProduct) {
        let conceptId = product.conceptId
        guard var cart = self.cart[conceptId] else { return }
        queue.async(flags: .barrier) {
            if let index = cart.firstIndex(where: { $0.productHash == product.productHash }) {
                cart.remove(at: index)
            }
        }
        
        delegates.forEach { delegate in
            delegate.removeEntireFromCart(product: product)
            delegate.totalDidUpdate(total: self.getTotal(conceptId: conceptId))
        }
    }
    
    public func getTotal(conceptId: String) -> Float {
        var total: Float = 0.0
        queue.sync {
            guard let cart = self.cart[conceptId] else { return }
            for product in cart {
                let weight = product.getWeight()
                var modifiersPrice: Float = 0
                if let modifiers = product.orderModifiers {
                    for modifier in modifiers {
                        for option in modifier.options {
                            modifiersPrice += option.price * weight
                        }
                    }
                }
                guard let count = product.count else { return }
                total += (product.getPrice() + modifiersPrice) * count
            }
        }
        return total
    }
    
    // MARK: - Images
    
    public func getImage(badge: CWBadge, completion: @escaping (UIImage?) -> Void) {
        getImage(id: badge._id, url: badge.image?.body) { image in
            completion(image)
        }
    }
    
    public func getImage(product: CWProduct, completion: @escaping (UIImage?) -> Void) {
        getImage(id: product._id, url: product.image?.body) { image in
            completion(image)
        }
    }
    
    public func getImage(category: CWCategory, completion: @escaping (UIImage?) -> Void) {
        getImage(id: category._id, url: category.image?.body) { image in
            completion(image)
        }
    }
    
    public func getImage(concept: CWConcept, completion: @escaping (UIImage?) -> Void) {
        getImage(id: concept._id, url: concept.image?.body) { image in
            completion(image)
        }
    }
    
    private func getImage(id: String, url: String?, completion: @escaping (UIImage?) -> Void) {
        guard let url = url, let urlRequest = prepareURLRequest(forPath: url, completion: completion), let imageCache = imageCache else { return }
        if let image = imageCache.image(for: urlRequest, withIdentifier: id) {
            completion(image)
        } else {
            guard let downloader = downloader else { return }
            downloader.download(urlRequest, completion:  { response in
                if case .success(let image) = response.result {
                    imageCache.add(image, for: urlRequest, withIdentifier: id)
                    completion(image)
                }
            })
        }
    }
    
    private func prepareURLRequest(forPath: String?, completion: @escaping (UIImage?) -> ()) -> URLRequest? {
        guard let path = forPath else {
            completion(nil)
            return nil
        }
        guard let url = URL(string: path) else {
            completion(nil)
            return nil
        }
        return URLRequest(url: url)
    }
    
    // MARK: - Stories
    
    /// Get the stories by concept or all company's stories.
    ///
    /// - Parameters:
    ///   - conceptId:  The concept Id. Can be null.
    ///
    /// - Returns: A stories and error for the given `conceptId` or for all `concepts` in company.
    public func getStories(conceptId concept: String? = nil, page: Int64 = 1, completion: @escaping([CWStory], NSError?) -> Void) {
        let params = CWStoryRequest(conceptId: concept, limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/stories/v1/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWStoryResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }
                case .failure(let err):
                    completion([], err as NSError)
                }
            }
    }
    
    // MARK: - Menu
    
    public func getMenu(concept: CWConcept? = nil, groupId group: String? = nil, terminal: CWTerminal? = nil, page: Int64 = 1, completion: @escaping(CWMenu?, NSError?) -> Void) {
        var menu = CWMenu()
        
        let menuGroup = DispatchGroup()
        
        menuGroup.enter()
        getCategories(concept: concept, groupId: group, terminal: terminal, page: page) { (categories, err) in
            if let err = err {
                completion(nil, err)
            }
            
            menu.categories = categories
            menuGroup.leave()
        }
        
        menuGroup.enter()
        getProducts(concept: concept, groupId: group, terminal: terminal, page: page) { (products, err) in
            if let err = err {
                completion(nil, err)
            }
            
            menu.products = products
            menuGroup.leave()
        }
        
        menuGroup.notify(queue: .main) {
            completion(menu, nil)
        }
    }
    
    public func getCategories(concept: CWConcept? = nil, groupId group: String? = nil, terminal: CWTerminal? = nil, page: Int64 = 1, completion: @escaping([CWCategory], NSError?) -> Void) {
        let params = CWMenuRequest(conceptId: concept?._id, groupId: group, terminalId: terminal?._id, search: nil, limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/categories/v1/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWCategoryResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }
                    
                case .failure(let err):
                    completion([], err as NSError)
                }
            }
    }
    
    public func getProducts(concept: CWConcept? = nil, groupId group: String? = nil, terminal: CWTerminal? = nil, page: Int64 = 1, completion: @escaping([CWProduct], NSError?) -> Void) {
        let params = CWMenuRequest(conceptId: concept?._id, groupId: group, terminalId: terminal?._id, search: nil, limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/products/v1/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWProductResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }

                case .failure(let err):
                    debugPrint(err)
                    completion([], err as NSError)
                }
            }
    }
    
    public func getFavorites(conceptId concept: String, page: Int64 = 1, completion: @escaping([CWProduct], NSError?) -> Void) {
        let params = CWFavoriteRequest(conceptId: concept, limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/favorite/v1/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWProductResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }

                case .failure(let err):
                    debugPrint(err)
                    completion([], err as NSError)
                }
            }
    }
    
    public func addFavorite(product: CWProduct, completion: @escaping(NSError?) -> Void) {
        let params = CWFavoriteRequest(conceptId: product.conceptId, productCode: product.code)
        
        AF.request("\(uri)/favorite/v1/", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .response() { resp in
                switch resp.result {
                case .success(_):
                    completion(nil)
                case .failure(let err):
                    debugPrint(err)
                    completion(err as NSError)
                }
            }
    }
    
    public func deleteFavorite(product: CWProduct, completion: @escaping(NSError?) -> Void) {
        let params = CWFavoriteRequest(conceptId: product.conceptId, productCode: product.code)
        
        AF.request("\(uri)/favorite/v1/", method: .delete, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .response() { resp in
                switch resp.result {
                case .success(_):
                    completion(nil)
                case .failure(let err):
                    debugPrint(err)
                    completion(err as NSError)
                }
            }
    }
    
    // MARK: - Concepts
    public func getConcepts(page: Int64 = 1, completion: @escaping([CWConcept], NSError?) -> Void) {
        let params = CWConceptRequest(limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/concepts/v1/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWConceptResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }
                    
                case .failure(let err):
                    completion([], err as NSError)
                }
            }
    }
    
    // MARK: - Terminals
    public func getTerminals(page: Int64 = 1, completion: @escaping([CWTerminal], NSError?) -> Void) {
        let params = CWTerminalRequest(limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/terminals/v1/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWTerminalResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }
                    
                case .failure(let err):
                    completion([], err as NSError)
                }
            }
    }
    
    // MARK: - Private methods
    fileprivate func productHash(product: CWProduct, modifiers: [CWModifier]) -> String {
        let mString = "\(product._id)\(modifiers.map { $0.options.map { $0.name }.joined() }.joined())"
        let digest = Insecure.SHA1.hash(data: mString.data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    fileprivate func parsePhone(phone: String) -> Int64 {
        let regex = try! NSRegularExpression(pattern: "[\\+\\(\\)\\s?\\-]", options: NSRegularExpression.Options.caseInsensitive)
        let range = NSMakeRange(0, phone.count)
        var modString = regex.stringByReplacingMatches(in: phone, options: [], range: range, withTemplate: "")
        modString.remove(at: modString.startIndex)
        let parsedPhone = Int64(modString)
        
        if let parsedPhone = parsedPhone {
            return parsedPhone
        }
        
        return 0
    }
    
    // MARK: - CoreData methods
    fileprivate func updateToken(token: String) {
        let fetchRequest: NSFetchRequest<CWDUser> = CWDUser.fetchRequest()
        
        do {
            let users = try persistentContainer.viewContext.fetch(fetchRequest)
            var user: CWDUser
            
            if let existing = users.first {
                user = existing
            } else {
                user = NSEntityDescription.insertNewObject(forEntityName: "CWDUser", into: persistentContainer.viewContext) as! CWDUser
            }
            
            user.token = token
        } catch let error as NSError {
            os_log("can't fetch the user from coreData: %@", type: .error, error.localizedDescription)
        }
        
        do {
            try persistentContainer.viewContext.save()
        } catch let error as NSError {
            os_log("can't save the access_token to coreData: %@", type: .error, error.localizedDescription)
        }
        
    }
    
    // MARK: - Core Data stack
    lazy var persistentContainer: NSPersistentContainer = {
//        let frameworkBundle = Bundle(for: type(of: self))
//        print(frameworkBundle.bundleIdentifier)
//        guard let modelURL = frameworkBundle.url(forResource: "CWData", withExtension: "xcdatamodel") else {
//
//            fatalError("Unable to load persistent stores")
//        }
//        let managedObjectModel =  NSManagedObjectModel(contentsOf: modelURL)
//
//        let container = NSPersistentContainer(name: "CWData", managedObjectModel: managedObjectModel!)
//        container.loadPersistentStores { storeDescription, error in
//            if let error = error {
//                fatalError("Unable to load persistent stores: \(error)")
//            }
//        }
//
        let container = NSPersistentContainer(name: "CWData")
        
        debugPrint(container)
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        return container
    }()
    
    // MARK: - Core Data Saving support
    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
}

extension CW: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }
}
