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

let version = "0.0.68"
let uri = "https://customer.api.cw.marketing/api"
let paymentUri = "https://payments.cw.marketing/v1/create"

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
    
    /// Creates an instance
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
        
        if let source = config.source {
            headers.add(name: "Source-Id", value: source)
        }
        
        if let cacheRules = config.cacheRules {
            imageCache = AutoPurgingImageCache(memoryCapacity: cacheRules.memoryCapacity, preferredMemoryUsageAfterPurge: cacheRules.usageAfterPurge)
            let diskCache = URLCache(memoryCapacity: 0, diskCapacity: cacheRules.diskCapacity, diskPath: "marketing.cw.disk_cache")
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = diskCache
            downloader = ImageDownloader(configuration: configuration, imageCache: imageCache)
        }
        
        self.getConcepts(withInit: true) { (_, _) in }
    }
    
    // MARK: - Check auth
    public func checkToken() throws -> String {
        do {
            let user = try self.coreDataManager.user()
            return user.token ?? ""
        } catch {
            throw error
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
                        self.headers.add(name: "Authorization", value: "Bearer \(token)")
                        
                        do {
                            try self.updateToken(token: token)
                        } catch {
                            completion(nil, error as NSError)
                        }
                    }
                    completion(val, nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("auth error response: %@", type: .error, errResp)
                    }
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
                    completion(val, nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("signup error response: %@", type: .error, errResp)
                    }
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
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("requestCode error response: %@", type: .error, errResp)
                    }
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
                var weight: Float = 1
                if product.weight.min > 0 {
                    weight = product.weight.min
                }
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
    
    public func getImage(product: CWProduct, preview: Bool = false, completion: @escaping (UIImage?) -> Void) {
        if preview {
            getImage(id: "\(product._id)_preview", url: product.previewImage?.body) { image in
                completion(image)
            }
        } else {
            getImage(id: product._id, url: product.image?.body) { image in
                completion(image)
            }
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
    
    public func getImage(notification: CWNotification, completion: @escaping (UIImage?) -> Void) {
        getImage(id: notification._id, url: notification.image?.body) { image in
            completion(image)
        }
    }
    
    public func getImage(content: CWContent, completion: @escaping (UIImage?) -> Void) {
        getImage(id: content._id, url: content.image) { image in
            completion(image)
        }
    }
    
    public func getImage(story: CWStory, completion: @escaping (UIImage?) -> Void) {
        getImage(id: story._id, url: story.preview.body) { image in
            completion(image)
        }
    }
    
    public func getImage(image: CWImage, completion: @escaping (UIImage?) -> Void) {
        getImage(id: image.body, url: image.body) { image in
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
    
    // MARK: - Transactions
    public func getTransactions(completion: @escaping([CWTransaction], NSError?) -> Void) {
        AF.request("\(uri)/v1/transactions/", method: .get, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWTransactionResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    } else {
                        completion([], nil)
                    }
                case .failure(let err):
                    os_log("getTransactions err: %@", type: .error, err as CVarArg)
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getTransactions response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    // MARK: - Profile
    public func updateProfile(_ profile: CWProfileUpdateRequest, completion: @escaping(NSError?) -> Void) {
        AF.request("\(uri)/v1/me/profile", method: .put, parameters: profile, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWProfile.self) { resp in
                switch resp.result {
                case .success(_):
                    completion(nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("updateProfile response: %@", type: .error, errResp)
                    }
                    completion(err as NSError)
                }
            }
    }
    
    public func getProfile(completion: @escaping(CWProfile?, NSError?) -> Void) {
        AF.request("\(uri)/v1/me/profile", method: .get, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWProfile.self) { resp in
                switch resp.result {
                case .success(let val):
                    do {
                        try self.updateProfile(profile: val)
                    } catch {
                        completion(nil, error as NSError)
                    }
                    completion(val, nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getProfile response: %@", type: .error, errResp)
                    }
                    completion(nil, err as NSError)
                }
            }
    }
    
    public func logout() throws {
        try coreDataManager.deleteUser()
        self.token = ""
        self.headers.remove(name: "Authorization")
        // TODO: - send push_token for delete
    }
    
    public func deleteProfile(completion: @escaping(NSError?) -> Void) {
        AF.request("\(uri)/v1/me/profile", method: .delete, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseString { resp in
                switch resp.result {
                case .success(_):
                    do {
                        try self.logout()
                    } catch {
                        completion(error as NSError)
                    }
                    completion(nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("deleteProfile response: %@", type: .error, errResp)
                    }
                    completion(err as NSError)
                }
            }
    }
    
    public func updatePushToken(token: String, completion: @escaping(NSError?) -> Void) {
        AF.request("\(uri)/v1/me/fcm?push_token=\(token)", method: .put, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseString { resp in
                switch resp.result {
                case .success(_):
                    completion(nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: .utf8) {
                        os_log("updatePushToken error response: %@", type: .error, errResp)
                    }
                    completion(err as NSError)
                }
            }
    }
    
    // MARK: - Promocode
    public func checkPromocode(code: String, concept: CWConcept, products p: [CWProduct], completion: @escaping(CWPromocode?, NSError?) -> Void) {
        var products: [CWPromocodeProduct] = []
        
        for product in p {
            var modifiers: [CWPromocodeProductModifier] = []
            if let m = product.orderModifiers {
                for modifier in m {
                    modifiers.append(CWPromocodeProductModifier(id: modifier._id, amount: product.count ?? 1))
                }
            }
            
            products.append(CWPromocodeProduct(code: product.code, amount: product.count ?? 1, modifiers: modifiers))
        }
        
        let params = CWPromocodeRequest(promocode: code, conceptId: concept._id, products: products)
        AF.request("\(uri)/v1/promocodes/", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
            .responseDecodable(of: CWPromocodeResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if var product = val.product {
                        product.isFromPromocode = true
                        completion(CWPromocode(product: product), nil)
                    }
                    
                    if let err = val.detail {
                        if err == "Promocode not found" {
                            completion(CWPromocode(product: nil, minOrderSum: nil, reason: .notFound), nil)
                        }
                        
                        if err.contains("total order cost should be more minimal cost") {
                            let minSum = err.filter { "0"..."9" ~= $0 }
                            completion(CWPromocode(product: nil, minOrderSum: Float(minSum), reason: .minOrderSum), nil)
                        }
                    }
                    
                    if let err = val.err {
                        if err == "promocode didn't start or was expired" {
                            completion(CWPromocode(product: nil, minOrderSum: nil, reason: .outdated), nil)
                        }
                    }
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("checkPromocode error response: %@", type: .error, errResp)
                    }
                    completion(nil, err as NSError)
                }
            }
    }
    
    // MARK: - Address
    public func getAddresses() throws -> [CWAddress] {
        do {
            let addresses = try self.coreDataManager.addresses()
            var cwaddresses: [CWAddress] = []
            
            for a in addresses {
                if let id = a.id, let city = a.city, let street = a.street, let home = a.home {
                    cwaddresses.append(CWAddress(_id: a.externalId ?? "", id: id, city: city, street: street, home: home, flat: a.flat, floor: a.floor, entrance: a.entrance, lat: a.lat, lon: a.lon))
                }
            }
            
            return cwaddresses
        } catch {
            throw error
        }
    }
    
    public func addAddress(address: CWAddress) throws {
        let a = coreDataManager.newAddress()
        
        a.setValue(UUID(), forKey: "id")
        a.setValue(address.city, forKey: "city")
        a.setValue(address.street, forKey: "street")
        a.setValue(address.home, forKey: "home")
        a.setValue(address.flat, forKey: "flat")
        a.setValue(address.floor, forKey: "floor")
        a.setValue(address.entrance, forKey: "entrance")
        a.setValue(address.lat, forKey: "lat")
        a.setValue(address.lon, forKey: "lon")
        a.setValue(Date(), forKey: "createdAt")
        a.setValue(Date(), forKey: "updatedAt")
        
        try coreDataManager.save()
    }
    
    public func updateAddress(address: CWAddress) {
        
    }
    
    public func deleteAddress(id: UUID) throws {
        try coreDataManager.deleteAddress(id: id)
    }
    
    // MARK: - Properties
    public func getProperties(name: String, completion: @escaping(String?, NSError?) -> Void) {
        AF.request("\(uri)/v1/properties_of_companies/bulk/\(name)", method: .get, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseJSON { resp in
                switch resp.result {
                case .success(let val):
                    os_log("getProperties error response: %@", type: .info, val)
                    if let data = val as? String, let dict = self.convertToDictionary(text: data), let property = dict[name] as? String {
                        completion(property, nil)
                    } else {
                        completion(nil, nil)
                    }
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getProperties error response: %@", type: .error, errResp)
                    }
                    completion(nil, err as NSError)
                }
            }
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
        
        AF.request("\(uri)/v1/stories/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWStoryResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getStories error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    // MARK: - Notifications
    public func getNotifications(page: Int64 = 1, completion: @escaping([CWNotification], NSError?) -> Void) {
        let params = CWStoryRequest(limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/v1/notifications/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWNotificationResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getNotifications error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    public func getNotificationBy(id: String, completion: @escaping(CWNotification?, NSError?) -> Void) {
        completion(nil, nil)
    }
    
    // MARK: - Contents
    public func getContents(concept: CWConcept? = nil, page: Int64 = 1, completion: @escaping([CWContent], NSError?) -> Void) {
        let params = CWStoryRequest(conceptId: concept?._id, limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/v1/contents/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWContentResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getContents error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    public func getContentsBy(id: String, completion: @escaping(CWNotification?, NSError?) -> Void) {
        completion(nil, nil)
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
        
        menuGroup.enter()
        getFeatured(concept: concept, page: page) { (featured, err) in
            if let err = err {
                completion(nil, err)
            }
            
            if featured.count > 0 {
                menu.featured = featured[0].products
            }
            menuGroup.leave()
        }
        
        menuGroup.notify(queue: .main) {
            completion(menu, nil)
        }
    }
    
    public func getCategories(concept: CWConcept? = nil, groupId group: String? = nil, terminal: CWTerminal? = nil, page: Int64 = 1, completion: @escaping([CWCategory], NSError?) -> Void) {
        let params = CWMenuRequest(conceptId: concept?._id, groupId: group, terminalId: terminal?._id, isDisabled: "false", isDeleted: "false", search: nil, limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/v1/categories/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWCategoryResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        let clearedData = data.filter { !$0.isDisabled && !$0.isDeleted }.sorted { $0.order ?? 0 < $1.order ?? 0}
                        completion(clearedData, nil)
                    }
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getCategories error response: %@", type: .error, errResp)
                    }
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
                        let clearedData = data.filter { !$0.isDisabled && !$0.isDeleted }.sorted { $0.order ?? 0 < $1.order ?? 0}
                        completion(clearedData, nil)
                    }
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getProducts error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    public func getProductBy(code: String, completion: @escaping(CWProduct?, NSError?) -> Void) {
        AF.request("\(uri)/v1/products/code/\(code)", method: .get, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWProduct.self) { resp in
                switch resp.result {
                case .success(let val):
                    completion(val, nil)
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getProductBy code error response: %@", type: .error, errResp)
                    }
                    completion(nil, err as NSError)
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
                    
                    if let detail = val.detail {
                        completion([], NSError(domain: detail, code: 400))
                    }
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getFavorites error response: %@", type: .error, errResp)
                    }
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
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("addFavorite error response: %@", type: .error, errResp)
                    }
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
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("deleteFavorite error response: %@", type: .error, errResp)
                    }
                    completion(err as NSError)
                }
            }
    }
    
    // MARK: - Concepts
    public func getConcepts(page: Int64 = 1, withInit: Bool? = false, completion: @escaping([CWConcept], NSError?) -> Void) {
        let params = CWConceptRequest(limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/v1/concepts/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWConceptResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        if let withInit = withInit, withInit {
                            self.initCart(concepts: data)
                            self.initConcepts(concepts: data)
                        }
                        completion(data, nil)
                    }
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getConcepts error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    // MARK: - Terminals
    public func getTerminals(concept: CWConcept?, page: Int64 = 1, completion: @escaping([CWTerminal], NSError?) -> Void) {
        var params = CWTerminalRequest(limit: self.config.defaultLimitPerPage, page: page)
        if let concept = concept {
            params.conceptId = concept._id
        }
        
        AF.request("\(uri)/v1/terminals/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWTerminalResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getTerminals error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    public func getGeoJSON(_ terminal: CWTerminal, completion: @escaping(Data?, NSError?) -> Void) {
        guard let geojsonUrl = terminal.geojson else {
            completion(nil, NSError(domain: "error", code: 3001, userInfo: ["error": "can't get geojson url"]))
            return
        }
        
        AF.request(geojsonUrl, method: .get, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseData { resp in
                switch resp.result {
                case .success(let val):
                    completion(val, nil)
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getTerminals error response: %@", type: .error, errResp)
                    }
                    completion(nil, err as NSError)
                }
            }
    }
    
    // MARK: - Featured products in card
    public func getFeatured(concept: CWConcept? = nil, page: Int64 = 1, completion: @escaping([CWFeatured], NSError?) -> Void) {
        let params = CWFeaturedRequest(conceptId: concept?._id, limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/v1/featured_products/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWFeaturedResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        completion(data, nil)
                    }
                    
                    if let detail = val.detail {
                        completion([], NSError(domain: "CWMarketing", code: 1000, userInfo: ["detail": detail]))
                    }
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getFeatured error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    // MARK: - Order
    public func getOrders(page: Int64 = 1, limit: Int64?, completion: @escaping([CWUserOrder], NSError?) -> Void) {
        let l = limit != nil ? limit : self.config.defaultLimitPerPage
        let params = CWUserOrderRequest(limit: l, page: page)
        
        AF.request("\(uri)/v1/orders/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWUserOrderResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        var orders = data
                        var cs: [CWDConcept] = []
                        var ts: [CWDTerminal] = []
                        var pts: [CWDPaymentType] = []
                        var dts: [CWDDeliveryType] = []
                        
                        do {
                            cs = try self.coreDataManager.concepts()
                            for c in cs {
                                if let terminals = c.terminal {
                                    for case let p as CWDTerminal in terminals {
                                        ts.append(p)
                                    }
                                }
                                
                                if let paymentTypes = c.payment {
                                    for case let p as CWDPaymentType in paymentTypes {
                                        pts.append(p)
                                    }
                                }
                                
                                if let deliveryTypes = c.delivery {
                                    for case let p as CWDDeliveryType in deliveryTypes {
                                        dts.append(p)
                                    }
                                }
                            }
                            
                            for (i, d) in orders.enumerated() {
                                for c in cs {
                                    if d.conceptId == c.externalId {
                                        orders[i].concept = CWConcept(_id: c.externalId ?? "", name: c.name ?? "N/A", isDeleted: false, isDisabled: false, mainGroupId: "", mainTerminalId: "", tpcasId: "")
                                    }
                                }
                                
                                for t in ts {
                                    if d.terminalId == t.externalId {
                                        orders[i].terminal = CWTerminal(_id: t.externalId ?? "", address: t.address ?? "N/A", city: t.city ?? "N/A", timezone: t.timezone ?? "N/A", conceptId: t.conceptId ?? "N/A", groupId: "", companyId: "")
                                    }
                                }
                                
                                for p in pts {
                                    if d.paymentTypeId == p.externalId {
                                        orders[i].paymentType = CWPaymentType(_id: p.externalId ?? "N/A", name: p.name ?? "N/A", code: p.code ?? "N/A", isExternal: p.isExternal)
                                    }
                                }
                                
                                for p in dts {
                                    if d.deliveryTypeId == p.externalId {
                                        orders[i].deliveryType = CWDeliveryType(_id: p.externalId ?? "N/A", name: p.name ?? "N/A", code: p.code ?? "N/A")
                                    }
                                }
                            }
                        } catch {
                            print(error.localizedDescription)
                        }
                        
                        let group = DispatchGroup()
                        
                        for (i, o) in orders.enumerated() {
                            group.enter()
                            self.getOrderFeedback(order: o) { feedback, _ in
                                if let feedback = feedback {
                                    orders[i].feedback = feedback
                                }
                                group.leave()
                            }
                        }
                        
                        group.notify(queue: .main) {
                            completion(orders, nil)
                        }
                    }
                    
                    if let detail = val.detail {
                        completion([], NSError(domain: "CWMarketing", code: 1000, userInfo: ["detail": detail]))
                    }
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getOrders error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    public func getOrderBy(id: String, page: Int64 = 1, completion: @escaping(CWUserOrder?, NSError?) -> Void) {
        let params = CWUserOrderRequest(limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/v1/orders/\(id)", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWUserOrder.self) { resp in
                switch resp.result {
                case .success(let val):
                    completion(val, nil)
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getOrderBy id error response: %@", type: .error, errResp)
                    }
                    completion(nil, err as NSError)
                }
            }
    }
    
    public func rateOrder(order: CWUserOrder, score: Int64, comment: String, completion: @escaping(NSError?) -> Void) {
        let params = CWUserOrderFeedbackRequest(body: comment, score: score, orderId: order._id)
        AF.request("\(uri)/v1/feedbacks/", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .response { resp in
                switch resp.result {
                case .success(_):
                    completion(nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("rateOrder error response: %@", type: .error, errResp)
                    }
                    completion(err as NSError)
                }
            }
    }
    
    public func rateOrder(score: Int64, comment: String, completion: @escaping(NSError?) -> Void) {
        let params = CWUserOrderFeedbackRequest(body: comment, score: score, orderId: nil)
        AF.request("\(uri)/v1/feedbacks/", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .response { resp in
                switch resp.result {
                case .success(_):
                    completion(nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("rateOrder error response: %@", type: .error, errResp)
                    }
                    completion(err as NSError)
                }
            }
    }
    
    public func getOrderFeedback(order: CWUserOrder, completion: @escaping(CWUserOrderFeedback?, NSError?) -> Void) {
        let params = CWUserOrderFeedbackGetRequest(limit: 1, page: 1, orderId: order._id)
        AF.request("\(uri)/v1/feedbacks/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWUserOrderFeedbackResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data, data.count > 0 {
                        completion(data[0], nil)
                    } else {
                        completion(nil, nil)
                    }
                    
                    if let detail = val.detail {
                        completion(nil, NSError(domain: "CWMarketing", code: 1000, userInfo: ["detail": detail]))
                    }
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getOrderFeedback error response: %@", type: .error, errResp)
                    }
                    completion(nil, err as NSError)
                }
            }
    }
    
    public func deliveryCheck(concept: CWConcept, address: CWAddress, completion: @escaping(CWDeliveryCheck?, NSError?) -> Void) {
        let params = CWDeliveryCheckRequest(conceptId: concept._id, address: CWDeliveryCheckAddress(city: address.city, street: address.street, home: address.home))
        
        AF.request("\(uri)/v1/delivery/check/", method: .post, parameters: params, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWDeliveryCheck.self) { resp in
                switch resp.result {
                case .success(let val):
                    completion(val, nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("deliveryCheck error response: %@", type: .error, errResp)
                    }
                    completion(nil, err as NSError)
                }
            }
    }
    
    public func send(order: CWOrder, isExternal: Bool = false, completion: @escaping(Bool, String?, NSError?) -> Void) {
        var o = CWOrderRequest(companyId: config.companyId, sourceId: config.source ?? "")
        o.prepare(order: order)
        
        AF.request("\(uri)/v1/orders/order", method: .post, parameters: o, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWOrderResponse.self) { resp in
                switch resp.result {
                case .success(let res):
                    if isExternal {
                        guard let awsId = res.message.components(separatedBy: " - ").last else { return completion(false, nil, NSError(domain: "Не удалось получить id заказа", code: 90001)) }
                        self.getOnlinePaymentLink(id: awsId) { link in
                            completion(true, link, nil)
                        }
                    }
                    completion(true, nil, nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("send order error response: %@", type: .error, errResp)
                    }
                    completion(false, nil, err as NSError)
                }
            }
    }
    
    public func getPaymentTypes(concept: CWConcept, completion: @escaping([CWPaymentType], NSError?) -> Void) {
        let params = CWPaymentTypeRequest(conceptId: concept._id)
        
        AF.request("\(uri)/v1/payments_types/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: [CWPaymentType].self) { resp in
                switch resp.result {
                case .success(let val):
                    completion(val, nil)
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getPaymentTypes error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    public func getDeliveryTypes(concept: CWConcept, completion: @escaping([CWDeliveryType], NSError?) -> Void) {
        let params = CWDeliveryTypeRequest(conceptId: concept._id)
        
        AF.request("\(uri)/v1/delivery_types/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: [CWDeliveryType].self) { resp in
                switch resp.result {
                case .success(let val):
                    completion(val, nil)
                    
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getDeliveryTypes error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
                }
            }
    }
    
    // MARK: - Support
    public func send(support: CWSupport, completion: @escaping(Bool, NSError?) -> Void) {
        var supportRequest = support
        
        do {
            let user = try coreDataManager.user()
            if let id = user.id {
                supportRequest.customerId = id
            }
        } catch {
            os_log("cant get user id from core data: %@", type: .error, error.localizedDescription)
        }
        
        AF.request("\(uri)/v1/supports/", method: .post, parameters: supportRequest, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWDeliveryCheck.self) { resp in
                switch resp.result {
                case .success(_):
                    completion(true, nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("send support error response: %@", type: .error, errResp)
                    }
                    completion(false, err as NSError)
                }
            }
    }
    
    
    // MARK: - Private methods
    fileprivate func getOnlinePaymentLink(id: String, completion: @escaping(String) -> Void) {
        AF.request("\(paymentUri)?id=\(id)", method: .post, parameters: CWOnlinePaymentRequest(id: id), encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWOnlinePaymentResponse.self) { resp in
                switch resp.result {
                case .success(let res):
                    completion(res.onlinePayment.formUrl)
                case .failure(_):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("send support error response: %@", type: .error, errResp)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.getOnlinePaymentLink(id: id, completion: completion)
                    }
                }
            }
    }
    
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
    
    fileprivate func initConcepts(concepts: [CWConcept]) {
        var res = concepts
        let group = DispatchGroup()
        
        for (i, c) in concepts.enumerated() {
            group.enter()
            getTerminals(concept: c) { (t, err) in
                if let err = err {
                    os_log("initConcepts cant get terminals by concept %{public}@", type: .error, err.localizedDescription)
                    return
                }
                res[i].terminals = t
                group.leave()
            }
            
            group.enter()
            getPaymentTypes(concept: c) { (t, err) in
                if let err = err {
                    os_log("initConcepts cant get paymentTypes by concept %{public}@", type: .error, err.localizedDescription)
                    return
                }
                res[i].paymentTypes = t
                group.leave()
            }
            
            group.enter()
            getDeliveryTypes(concept: c) { (t, err) in
                if let err = err {
                    os_log("initConcepts cant get deliveryTypes by concept %{public}@", type: .error, err.localizedDescription)
                    return
                }
                res[i].deliveryTypes = t
                group.leave()
            }
        }
        
        
        group.notify(queue: .main) {
            for c in res {
                do {
                    try self.updateData(concept: c, terminals: c.terminals ?? [], paymentTypes: c.paymentTypes ?? [], deliveryTypes: c.deliveryTypes ?? [])
                } catch {
                    os_log("initConcepts cant updateData %{public}@", type: .error, error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - CoreData methods
    fileprivate func updateData(concept conceptData: CWConcept, terminals terminalsData: [CWTerminal], paymentTypes ptData: [CWPaymentType], deliveryTypes dtData: [CWDeliveryType]) throws {
        var terminals = try coreDataManager.terminalsBy(concept: conceptData._id)
        var insertDict: [String: CWDTerminal] = [:]
        for t in terminals {
            if let id = t.externalId {
                insertDict[id] = t
            }
        }
        
        for d in terminalsData {
            if insertDict[d._id] == nil {
                let c = coreDataManager.newTerminal()
                c.setValue(d.address, forKey: "address")
                c.setValue(d.city, forKey: "city")
                c.setValue(d.timezone, forKey: "timezone")
                c.setValue(d.delivery, forKey: "delivery")
                c.setValue(d._id, forKey: "externalId")
                c.setValue(d.order, forKey: "order")
                c.setValue(conceptData._id, forKey: "conceptId")
                c.setValue(Date(), forKey: "createdAt")
                c.setValue(Date(), forKey: "updatedAt")
                
                terminals.append(c)
            } else {
                if let c = try coreDataManager.terminalBy(id: d._id) {
                    c.setValue(d.address, forKey: "address")
                    c.setValue(d.city, forKey: "city")
                    c.setValue(d.timezone, forKey: "timezone")
                    c.setValue(d.delivery, forKey: "delivery")
                    c.setValue(d.order, forKey: "order")
                    c.setValue(d.conceptId, forKey: "conceptId")
                    c.setValue(Date(), forKey: "updatedAt")
                }
            }
        }
        
        var deleteDict: [String: CWTerminal] = [:]
        for d in terminalsData {
            deleteDict[d._id] = d
        }
        
        for t in terminals {
            if let id = t.externalId {
                if deleteDict[id] == nil {
                    try coreDataManager.deleteTerminal(id: id)
                    terminals.removeAll(where: { $0.externalId == id })
                }
            }
        }
        
        var paymentTypes = try coreDataManager.paymentTypesBy(concept: conceptData._id)
        var insertPDict: [String: CWDPaymentType] = [:]
        for p in paymentTypes {
            if let id = p.externalId {
                insertPDict[id] = p
            }
        }
        
        for d in ptData {
            if insertPDict[d._id] == nil {
                let c = coreDataManager.newPaymentType()
                c.setValue(d._id, forKey: "externalId")
                c.setValue(d.code, forKey: "code")
                c.setValue(d.name, forKey: "name")
                c.setValue(conceptData._id, forKey: "conceptId")
                c.setValue(d.isExternal, forKey: "isExternal")
                
                paymentTypes.append(c)
            } else {
                if let c = try coreDataManager.paymentTypeBy(id: d._id) {
                    c.setValue(d.code, forKey: "code")
                    c.setValue(d.name, forKey: "name")
                    c.setValue(conceptData._id, forKey: "conceptId")
                    c.setValue(d.isExternal, forKey: "isExternal")
                }
            }
        }
        
        var deletePDict: [String: CWPaymentType] = [:]
        for d in ptData {
            deletePDict[d._id] = d
        }
        
        for t in paymentTypes {
            if let id = t.externalId {
                if deletePDict[id] == nil {
                    try coreDataManager.deletePaymentType(id: id)
                    paymentTypes.removeAll(where: { $0.externalId == id })
                }
            }
        }
        
        var deliveryTypes = try coreDataManager.deliveryTypesBy(concept: conceptData._id)
        var insertDDict: [String: CWDDeliveryType] = [:]
        for p in deliveryTypes {
            if let id = p.externalId {
                insertDDict[id] = p
            }
        }
        
        for d in dtData {
            if insertPDict[d._id] == nil {
                let c = coreDataManager.newDeliveryType()
                c.setValue(d._id, forKey: "externalId")
                c.setValue(d.code, forKey: "code")
                c.setValue(d.name, forKey: "name")
                c.setValue(conceptData._id, forKey: "conceptId")
                
                deliveryTypes.append(c)
            } else {
                if let c = try coreDataManager.deliveryTypesBy(id: d._id) {
                    c.setValue(d.code, forKey: "code")
                    c.setValue(d.name, forKey: "name")
                    c.setValue(conceptData._id, forKey: "conceptId")
                }
            }
        }
        
        var deleteDDict: [String: CWDeliveryType] = [:]
        for d in dtData {
            deleteDDict[d._id] = d
        }
        
        for t in deliveryTypes {
            if let id = t.externalId {
                if deleteDDict[id] == nil {
                    try coreDataManager.deleteDeliveryType(id: id)
                    paymentTypes.removeAll(where: { $0.externalId == id })
                }
            }
        }
        
        if let c = try coreDataManager.conceptBy(id: conceptData._id) {
            c.setValue(conceptData.name, forKey: "name")
            c.setValue(conceptData.additionalData, forKey: "additionalData")
            c.setValue(conceptData.comment, forKey: "comment")
            c.setValue(conceptData.image?.body, forKey: "image")
            c.setValue(conceptData.order, forKey: "order")
            c.setValue(Date(), forKey: "updatedAt")
            
            for t in terminals {
                c.addToTerminal(t)
            }
            
            for p in paymentTypes {
                c.addToPayment(p)
            }
            
            for d in deliveryTypes {
                c.addToDelivery(d)
            }
        } else {
            let c = coreDataManager.newConcept()
            c.setValue(conceptData._id, forKey: "externalId")
            c.setValue(conceptData.name, forKey: "name")
            c.setValue(conceptData.additionalData, forKey: "additionalData")
            c.setValue(conceptData.comment, forKey: "comment")
            c.setValue(conceptData.image?.body, forKey: "image")
            c.setValue(conceptData.order, forKey: "order")
            c.setValue(Date(), forKey: "createdAt")
            c.setValue(Date(), forKey: "updatedAt")
            
            for t in terminals {
                c.addToTerminal(t)
            }
            
            for p in paymentTypes {
                c.addToPayment(p)
            }
            
            for d in deliveryTypes {
                c.addToDelivery(d)
            }
        }
        
        try coreDataManager.save()
    }
    
    fileprivate func updateToken(token: String) throws {
        let user = try coreDataManager.user()
        
        user.setValue(token, forKey: "token")
        
        try coreDataManager.save()
    }
    
    fileprivate func updateProfile(profile: CWProfile) throws {
        var dobDate: NSDate?
        
        if let dob = profile.dob {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            dobDate = dateFormatter.date(from: dob) as NSDate?
        }
        
        let user = try coreDataManager.user()
        
        user.setValue(profile._id, forKey: "id")
        user.setValue(profile.firstName, forKey: "firstName")
        user.setValue(profile.lastName, forKey: "lastName")
        user.setValue(profile.phone, forKey: "phone")
        user.setValue(profile.email, forKey: "email")
        user.setValue(profile.sex, forKey: "sex")
        user.setValue(dobDate, forKey: "dob")
        user.setValue(profile.card, forKey: "card")
        user.setValue(profile.externalId, forKey: "externalId")
        user.setValue(profile.wallet.card, forKey: "wallet")
        user.setValue(profile.balances.total, forKey: "balance")
        
        try coreDataManager.save()
    }
    
    func convertToDictionary(text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            } catch {
                print(error.localizedDescription)
            }
        }
        return nil
    }
    
}

extension CW: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }
}
