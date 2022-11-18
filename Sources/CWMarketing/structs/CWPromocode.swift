//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 18.11.2022.
//

import Foundation

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
    var product: String?
    var err: String?
    var minSum: Float?
}
