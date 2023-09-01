//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 17.11.2022.
//

import Foundation

public struct CWUserOrder: Codable {
    var _id: String
    public var number: Int
    public var address: CWUserOrderAddress?
    public var comment: String
    var conceptId: String
    public var deliveryTime: String
    var deliveryTypeId: String
    var paymentTypeId: String
    public var personsCount: Int
    public var products: [CWUserOrderProduct]
    var terminalId: String?
    public var withdrawBonuses: Float
    public var createdAt: String
    public var statusId: String?
    public var change: Float?
    
    @SkipCodable
    public var concept: CWConcept?
    @SkipCodable
    public var terminal: CWTerminal?
    @SkipCodable
    public var deliveryType: CWDeliveryType?
    @SkipCodable
    public var paymentType: CWPaymentType?
    @SkipCodable
    public var feedback: CWUserOrderFeedback?
}

public struct CWUserOrderAddress: Codable {
    public var city: String
    public var street: String
    public var home: String
    public var flat: Int?
    public var entrance: Int?
    public var floor: Int?
}

public struct CWUserOrderProduct: Codable {
    public var name: String
    public var amount: Float
    public var price: Float
    public var code: String
    public var weight: CWWeight
    public var productModifiers: [CWUserOrderProductModifier]?
}

public struct CWUserOrderProductModifier: Codable {
    public var group: String
    public var name: String
    public var price: Float
}

struct CWUserOrderRequest: Codable {
    var limit: Int64?
    var page: Int64?
}

struct CWUserOrderResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWUserOrder]?
    var detail: String?
}

public struct CWUserOrderFeedback: Codable {
    var _id: String
    public var body: String
    public var score: Int64
    var orderId: String
    public var createdAt: String
}

struct CWUserOrderFeedbackRequest: Codable {
    var body: String
    var score: Int64
    var orderId: String?
}

public struct CWUserOrderFeedbackGetRequest: Codable {
    var limit: Int64?
    var page: Int64?
    var orderId: String?
}

public struct CWUserOrderFeedbackResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWUserOrderFeedback]?
    var detail: String?
}

extension CWUserOrder {
    
    mutating func fill(concepts: [CWConcept], terminals: [CWTerminal], paymentTypes: [CWPaymentType], deliveryTypes: [CWDeliveryType]) {
        self.concept = concepts.first(where: { $0._id == self.conceptId })
        self.deliveryType = deliveryTypes.first(where: { $0._id == self.deliveryTypeId })
        self.paymentType = paymentTypes.first(where: { $0._id == self.paymentTypeId })
        
        if let terminalId = self.terminalId {
            self.terminal = terminals.first(where: { $0._id == terminalId })
        }
    }
    
}
