//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 18.11.2022.
//

import Foundation

public enum CWPromocodeError {
    case notFound
    case minOrderSum
    case outdated
}

public struct CWPromocode {
    public var product: CWProduct?
    public var minOrderSum: Float?
    public var reason: CWPromocodeError?
}

struct CWPromocodeProduct: Codable {
    var code: String
    var amount: Float
    var modifiers: [CWPromocodeProductModifier]
}

struct CWPromocodeProductModifier: Codable {
    var id: String
    var amount: Float
}

struct CWPromocodeRequest: Codable {
    var promocode: String
    var conceptId: String
    var products: [CWPromocodeProduct]
}

struct CWPromocodeResponse: Codable {
    var product: CWProduct?
    var err: String?
    var detail: String?
    var minSum: Float?
}
