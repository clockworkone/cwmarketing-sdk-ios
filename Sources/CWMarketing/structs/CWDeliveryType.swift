//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 08.11.2022.
//

import Foundation

public struct CWDeliveryType: Codable {
    var _id: String
    public var name: String
    public var code: String
}

struct CWDeliveryTypeRequest: Codable {
    var conceptId: String
}
