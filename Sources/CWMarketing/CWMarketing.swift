import Alamofire
import AlamofireImage
import UIKit

let version = "0.0.1"
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
    
    /// Creates an instance from a config.
    ///
    public init() {}
    
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
    
    public func getMenu(conceptId concept: String? = nil, groupId group: String? = nil, terminalId terminal: String? = nil, page: Int64 = 1, completion: @escaping(CWMenu?, NSError?) -> Void) {
        var menu = CWMenu()
        
        let menuGroup = DispatchGroup()
        
        menuGroup.enter()
        getCategories(conceptId: concept, groupId: group, terminalId: terminal, page: page) { (categories, err) in
            if let err = err {
                completion(nil, err)
            }
            
            menu.categories = categories
            menuGroup.leave()
        }
        
        menuGroup.enter()
        getProducts(conceptId: concept, groupId: group, terminalId: terminal, page: page) { (products, err) in
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
    
    public func getCategories(conceptId concept: String? = nil, groupId group: String? = nil, terminalId terminal: String? = nil, page: Int64 = 1, completion: @escaping([CWCategory], NSError?) -> Void) {
        let params = CWMenuRequest(conceptId: concept, groupId: group, terminalId: terminal, search: nil, limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/categories/v1/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWCategoryResponse.self) { resp in
                switch resp.result {
                case .success(let val):
                    if let data = val.data {
                        print(data)
                        completion(data, nil)
                    }
                    
                case .failure(let err):
                    completion([], err as NSError)
                }
            }
    }
    
    public func getProducts(conceptId concept: String? = nil, groupId group: String? = nil, terminalId terminal: String? = nil, page: Int64 = 1, completion: @escaping([CWProduct], NSError?) -> Void) {
        let params = CWMenuRequest(conceptId: concept, groupId: group, terminalId: terminal, search: nil, limit: self.config.defaultLimitPerPage, page: page)
        
        AF.request("\(uri)/products/v1/", method: .get, parameters: params, encoder: URLEncodedFormParameterEncoder.default, headers: self.headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CWProductResponse.self) { resp in
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
    
    public func getConcepts() {
        
    }
}

extension CW: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }
}


