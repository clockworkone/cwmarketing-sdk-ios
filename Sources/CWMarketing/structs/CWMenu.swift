//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 19.08.2022.
//

import Foundation

public struct CWMenu {
    public var categories: [CWCategory]
    public var products: [CWProduct]
    public var featured: [CWProduct]
    
    init() {
        self.categories = []
        self.products = []
        self.featured = []
    }
}

public struct CWCategory: Codable {
    public var _id: String
    public var parentCategory: String?
    public var name: String
    public var description: String?
    var externalId: String?
    public var image: CWImage?
    public var imageSize: String?
    var companyId: String
    var conceptId: String
    var terminalId: String
    public var order: Int64
    var slug: String?
    var source: String?
    var isHidden: Bool
    var isDisabled: Bool
}

extension Array where Element == CWCategory {
    
    public func byParent(category id: String) -> [CWCategory] {
        return filter { $0.parentCategory == id }
    }
    
}

public struct CWProduct: Codable {
    public var _id: String
    public var categoryId: String
    public var name: String
    public var description: String?
    var externalId: String?
    public var code: String
    public var unit: String
    public var price: Float
    public var weight: CWWeight
    public var image: CWImage?
    public var nutrition: CWNutrition
    public var modifiers: [CWModifier]?
    public var badges: [CWBadge]?
    public var featured: [CWProduct]?
    var companyId: String
    var conceptId: String
    var terminalId: String
    public var order: Int64
    var slug: String?
    var source: String?
    var isHidden: Bool
    var isDisabled: Bool
    
    @SkipCodable
    var productHash: String?
    @SkipCodable
    var orderModifiers: [CWModifier]?
    @SkipCodable
    public var count: Float?
}

extension Array where Element == CWProduct {
    
    public func by(category id: String) -> [CWProduct] {
        return filter { $0.categoryId == id }
    }
    
}

public struct CWWeight: Codable {
    public var full: Float
    public var min: Float
}

public struct CWNutrition: Codable {
    var energy: Float?
    var fiber: Float?
    var fat: Float?
    var carbohydrate: Float?
}

public struct CWModifier: Codable {
    var _id: String
    var name: String
    var externalId: String?
    var terminalId: String
    var order: Int64
    var image: CWImage?
    var source: String?
    var maxAmount: Float
    var minAmount: Float
    var required: Bool
    var isHidden: Bool
    var isDisabled: Bool
    var options: [CWOptions]
}

public struct CWOptions: Codable {
    var _id: String
    var name: String
    var externalId: String?
    var terminalId: String
    var order: Int64
    var image: CWImage?
    var source: String?
    var maxAmount: Float
    var minAmount: Float
    var required: Bool
    var isHidden: Bool
    var isDisabled: Bool
    var price: Float
}

public struct CWBadge: Codable {
    var _id: String
    var name: String
    var image: CWImage?
    var order: Int64
    var companyId: String
    var conceptId: String
    var isHidden: Bool
    var isDisabled: Bool
}

public struct CWFeatured: Codable {
    var _id: String
    var companyId: String
    var conceptId: String
    public var products: [CWProduct]
}

struct CWMenuRequest: Codable {
    var conceptId: String?
    var groupId: String?
    var terminalId: String?
    var search: String?
    var limit: Int64?
    var page: Int64?
}

struct CWCategoryResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWCategory]?
    var detail: String?
}

struct CWProductResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWProduct]?
    var detail: String?
}

struct CWFeaturedResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWFeatured]?
    var detail: String?
}
