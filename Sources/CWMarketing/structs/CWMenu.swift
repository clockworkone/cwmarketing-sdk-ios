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
    public var order: Int64?
    var slug: String?
    var source: String?
    var isHidden: Bool
    var isDisabled: Bool
    var isDeleted: Bool
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
    public var previewImage: CWImage?
    public var nutrition: CWNutrition
    public var modifiers: [CWModifier]?
    public var badges: [CWBadge]?
    public var featured: [CWProduct]?
    var companyId: String
    var conceptId: String
    var terminalId: String
    public var order: Int64?
    var slug: String?
    var source: String?
    var isHidden: Bool
    var isDisabled: Bool
    var isDeleted: Bool
    
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
    public var energy: Float?
    public var fiber: Float?
    public var fat: Float?
    public var carbohydrate: Float?
}

public struct CWModifier: Codable {
    public var _id: String
    public var name: String
    var externalId: String?
    var terminalId: String
    public var order: Int64?
    public var image: CWImage?
    var source: String?
    public var maxAmount: Float
    public var minAmount: Float
    public var required: Bool
    public var isHidden: Bool
    var isDisabled: Bool
    public var options: [CWOptions]
}

public struct CWOptions: Codable {
    public var _id: String
    public var name: String
    var externalId: String?
    var terminalId: String
    public var order: Int64?
    public var image: CWImage?
    var source: String?
    public var maxAmount: Float
    public var minAmount: Float
    public var required: Bool
    var isHidden: Bool
    var isDisabled: Bool
    public var price: Float
}

public struct CWBadge: Codable {
    public var _id: String
    public var name: String
    public var image: CWImage?
    public var order: Int64?
    var companyId: String?
    var conceptId: String
    var isHidden: Bool
    var isDisabled: Bool
}

public struct CWFeatured: Codable {
    var companyId: String
    var conceptId: String
    public var products: [CWProduct]
}

struct CWMenuRequest: Codable {
    var conceptId: String?
    var groupId: String?
    var terminalId: String?
    var isDisabled: String?
    var isDeleted: String?
    var search: String?
    var limit: Int64?
    var page: Int64?
}

struct CWFeaturedRequest: Codable {
    var conceptId: String?
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
