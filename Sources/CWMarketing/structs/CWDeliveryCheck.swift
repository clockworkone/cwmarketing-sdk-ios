//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 08.11.2022.
//

import Foundation

struct CWDeliveryCheckRequest: Codable {
    var conceptId: String
    var address: CWDeliveryCheckAddress
    
    public init(conceptId: String, address: CWDeliveryCheckAddress) {
        self.conceptId = conceptId
        self.address = address
    }
}

struct CWDeliveryCheckAddress: Codable {
    var city: String
    var street: String
    var home: String
    
    public init(city: String, street: String, home: String) {
        self.city = city
        self.street = street
        self.home = home
    }
}

public struct CWDeliveryCheck: Codable {
    public var isInDeliveryArea: Bool?
    public var minOrderSum: Float?
    public var areaName: String?
    public var deliveryTime: String?
    public var deliveryPrice: Float?
}
