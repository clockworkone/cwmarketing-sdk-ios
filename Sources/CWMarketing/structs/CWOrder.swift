//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 08.11.2022.
//

import Foundation

public struct CWOrder {
    public var concept: CWConcept
    public var terminal: CWTerminal?
    public var deliveryType: CWDeliveryType
    public var personsCount: Int?
    public var paymentType: CWPaymentType
    public var deliveryTime: Date?
    public var products: [CWProduct]
    public var address: CWAddress?
    public var withdrawBonuses: Float?
    public var comment: String?
    public var change: Float?
}


struct CWOrderRequest: Codable {
    var conceptId: String
    var companyId: String
    var terminalId: String?
    var deliveryTypeId: String
    var personsCount: Int
    var paymentTypeId: String
    var deliveryTime: String?
    var sourceId: String
    var withdrawBonuses: Float
    var comment: String
    var change: Float
    var address: CWOrderAddress?
    var products: [CWOrderProduct]
    
    public init(companyId: String, sourceId: String) {
        self.companyId = companyId
        self.sourceId = sourceId
        self.conceptId = ""
        self.deliveryTypeId = ""
        self.personsCount = 0
        self.paymentTypeId = ""
        self.withdrawBonuses = 0
        self.comment = ""
        self.change = 0
        self.products = []
    }
}

struct CWOrderResponse: Codable {
    var message: String
}

struct CWOrderAddress: Codable {
    var city: String
    var street: String
    var home: String
    var flat: Int64?
    var floor: Int64?
    var entrance: Int64?
}

struct CWOrderProduct: Codable {
    var code: String
    var amount: Float
    var modifiers: [CWOrderModifier]
}

struct CWOrderModifier: Codable {
    var id: String
    var amount: Float
}

extension CWOrderRequest {
    
    mutating func prepare(order: CWOrder) {
        self.conceptId = order.concept._id
        self.deliveryTypeId = order.deliveryType._id
        self.paymentTypeId = order.paymentType._id
        
        if let personsCount = order.personsCount {
            self.personsCount = personsCount
        }
        
        if let deliveryTime = order.deliveryTime {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd\'T\'HH:mm:ss\'.000\'Z"
            self.deliveryTime = dateFormatter.string(from: deliveryTime)
        }
        
        if order.terminal != nil && order.address == nil, let id = order.terminal?._id {
            self.terminalId = id
        } else {
            if let a = order.address {
                self.address = CWOrderAddress(city: a.city, street: a.street, home: a.home, flat: a.flat, floor: a.floor, entrance: a.entrance)
            }
        }
        
        var p: [CWOrderProduct] = []
        for product in order.products {
            var m: [CWOrderModifier] = []
            if let modifiers = product.orderModifiers {
                for modifier in modifiers {
                    m.append(CWOrderModifier(id: modifier._id, amount: product.count ?? 1))
                }
            }
            
            p.append(CWOrderProduct(code: product.code, amount: product.count ?? 1, modifiers: m))
        }
        
        self.products = p
    }
    
}
