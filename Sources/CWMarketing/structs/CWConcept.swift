//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 19.08.2022.
//

import Foundation

public struct CWConcept: Codable {
    public var _id: String
    public var name: String
    public var comment: String?
    public var image: CWImage?
    var isDeleted: Bool
    var isDisabled: Bool
    public var additionalData: String?
    var order: Int64?
    public var mainGroupId: String
    public var mainTerminalId: String
    var tpcasId: String
    
    @SkipCodable
    var terminals: [CWTerminal]?
    @SkipCodable
    var paymentTypes: [CWPaymentType]?
    @SkipCodable
    var deliveryTypes: [CWDeliveryType]?
}

struct CWConceptRequest: Codable {
    var limit: Int64?
    var page: Int64?
}

struct CWConceptResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWConcept]?
    var detail: String?
}
