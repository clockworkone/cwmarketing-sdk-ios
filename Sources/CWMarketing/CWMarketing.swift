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

let version = "0.0.24"
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
                        self.headers.add(name: "Authorization", value: "Bearer: \(token)")
                        
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
    
    // MARK: - Profile
    public func getProfile(completion: @escaping(CWProfile?, NSError?) -> Void) {
//        do {
//            let user = try self.coreDataManager.user()
//            let profile = CWProfile(_id: user.id ?? "", firstName: user.firstName ?? "",
//                                    lastName: user.lastName ?? "", phone: user.phone, sex: user.sex, card: user.card,
//                                    wallet: CWWallet(auth: nil, card: user.wallet), balances: CWBalances(total: user.balance, categories: [], balances: []))
//            completion(profile, nil)
//        } catch {
//            completion(nil, error as NSError)
//        }

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
    
    public func updatePushToken(token: String, completion: @escaping(NSError?) -> Void) {
        let params = CWProfileFCMRequest(push_token: token)
        
        AF.request("\(uri)/v1/me/fcm", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseString { resp in
                switch resp.result {
                case .success(_):
                    completion(nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("updatePushToken error response: %@", type: .error, errResp)
                    }
                    completion(err as NSError)
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
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getConcepts error response: %@", type: .error, errResp)
                    }
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
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("getTerminals error response: %@", type: .error, errResp)
                    }
                    completion([], err as NSError)
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
    public func getOrders(page: Int64 = 1, completion: @escaping([CWUserOrder], NSError?) -> Void) {
        let params = CWUserOrderRequest(limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/v1/orders/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWUserOrderResponse.self) { resp in
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
    
    public func send(order: CWOrder, completion: @escaping(Bool, NSError?) -> Void) {
        var o = CWOrderRequest(companyId: config.companyId, sourceId: config.source ?? "")
        o.prepare(order: order)
        
        AF.request("\(uri)/v1/orders/order", method: .post, parameters: o, encoder: JSONParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWOrderResponse.self) { resp in
                switch resp.result {
                case .success(_):
                    completion(true, nil)
                case .failure(let err):
                    if let data = resp.data, let errResp = String(data: data, encoding: String.Encoding.utf8) {
                        os_log("send order error response: %@", type: .error, errResp)
                    }
                    completion(false, err as NSError)
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
    fileprivate func updateData(concepts data: [CWConcept]) throws {
        let concepts = try coreDataManager.concepts()
        
        for d in data {
            
            for c in concepts {
                if d._id == c.externalId {
                    c.setValue(d.name, forKey: "name")
                    c.setValue(d.additionalData, forKey: "additionalData")
                    c.setValue(d.comment, forKey: "comment")
                    c.setValue(d.image?.body, forKey: "image")
                }
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
    
}

extension CW: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }
}
