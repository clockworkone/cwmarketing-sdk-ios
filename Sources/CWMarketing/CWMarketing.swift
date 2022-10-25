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

let version = "0.0.6"
let uri = "https://customer.api.cw.marketing/api"

public final class CW {
    
    public static var shared: CW = {
        let instance = CW()
        return instance
    }()
    
    private let coreDataManager: CWCoreDataManager
    private var headers = HTTPHeaders()
    private var config = CWConfig()
    private var imageCache: ImageRequestCache?
    private var downloader: ImageDownloader?
    private let queue = DispatchQueue(label: "marketing.cw.queue", attributes: .concurrent)
    private var cart: [String: [CWProduct]] = [:]
    private var token: String = ""
    
    public weak var delegate: CWMarketingDelegate?
    public var delegates: [CWMarketingDelegate] = []
    
    /// Creates an instance from a config.
    ///
    public init() {
        coreDataManager = CWCoreDataManager()
        
        do {
            let user = try coreDataManager.user()
            if let token = user.token, token != "" {
                self.headers.add(name: "Authorization", value: "Bearer \(token)")
                self.token = token
            }
        } catch {
            os_log("can't get the access_token: %@", type: .info, error.localizedDescription)
        }
        
        let applicationDocumentsDirectory: URL = {
            let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            return urls[urls.count-1]
        }()
        os_log("coreData dir: %@", type: .info, applicationDocumentsDirectory.description)
        
        os_log("CWMarketing loaded version: %@", type: .info, version)
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
        
        AF.request("\(uri)/v1/auth/token", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWAuthResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let token = val.access_token {
                        self.token = token
                        self.headers.add(name: "Authorization", value: "Bearer: \(token)")
                        
                        do {
                            try self.updateToken(token: token)
                        } catch {
                            os_log("can't update the access_token: %@", type: .error, error.localizedDescription)
                        }
                    }
                    completion(val, nil)
                case .failure(let err):
                    completion(nil, err as NSError)
                }
            }
    }
    
    public func signup(request params: CWSignupRequest, completion: @escaping(CWSignupResponse?, NSError?) -> Void) {
        AF.request("\(uri)/v1/auth/signup", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWSignupResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    print(val)
                    completion(nil, nil)
                case .failure(let err):
                    completion(nil, err as NSError)
                }
            }
    }
    
    public func requestCode(phone: String, completion: @escaping(CWCodeReponse?, NSError?) -> Void) {
        let params = CWAuthRequest(phone: parsePhone(phone: phone))
        
        AF.request("\(uri)/v1/auth/code", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
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
    private func initCart(concepts: [CWConcept]) {
        for concept in concepts {
            self.cart[concept._id] = []
        }
    }
    
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
        self.cart[concept._id] = []
        delegates.forEach { delegate in
            delegate.wipeCart()
            delegate.totalDidUpdate(total: 0.0)
        }
    }
    
    public func addToCart(product: CWProduct, modifiers: [CWModifier] = [], amount: Float = 1.0) {
        let conceptId = product.conceptId
        var p = product
        guard var cart = self.cart[conceptId] else { return }
        
        queue.async(flags: .barrier) {
            if let index = cart.firstIndex(where: { $0.productHash == self.productHash(product: p, modifiers: modifiers) }) {
                if var count = cart[index].count {
                    count += amount
                    cart[index].count = count
                }
            } else {
                p.count = amount
                p.orderModifiers = modifiers
                p.productHash = self.productHash(product: product, modifiers: modifiers)
                cart.append(p)
            }
            
            self.cart[conceptId] = cart
        }
        
        delegates.forEach { delegate in
            delegate.addToCart(product: p)
            delegate.totalDidUpdate(total: self.getTotal(conceptId: conceptId))
        }
    }
    
    public func removeFromCart(product: CWProduct, modifiers: [CWModifier] = [], amount: Float = 1.0) {
        let conceptId = product.conceptId
        guard var cart = self.cart[conceptId] else { return }
        
        queue.async(flags: .barrier) {
            if let index = cart.firstIndex(where: { $0.productHash == product.productHash }) {
                if var count = cart[index].count, count > amount {
                    count -= amount
                    cart[index].count = count
                } else {
                    cart.remove(at: index)
                }
            }
            
            self.cart[conceptId] = cart
        }
        
        delegates.forEach { delegate in
            delegate.removeFromCart(product: product)
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
            
            self.cart[conceptId] = cart
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
        
        AF.request("\(uri)/v1/stories", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
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
        
        AF.request("\(uri)/v1/categories", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
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
        
        AF.request("\(uri)/v1/products/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
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
        
        AF.request("\(uri)/v1/favorite/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
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
        
        AF.request("\(uri)/v1/favorite/", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
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
        
        AF.request("\(uri)/v1/favorite/", method: .delete, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
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
        
        AF.request("\(uri)/v1/concepts/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWConceptResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        self.initCart(concepts: data)
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
        
        AF.request("\(uri)/v1/terminals/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
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
    fileprivate func updateToken(token: String) throws {
        let user = try coreDataManager.user()
        user.setValue(token, forKey: "token")
        try coreDataManager.save()
    }
    
}

extension CW: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }
}
