//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 08.11.2022.
//

import Foundation

public struct CWPaymentType: Codable {
    var _id: String
    public var name: String
    public var code: String
    var isExternal: Bool
}

struct CWPaymentTypeRequest: Codable {
    var conceptId: String
}
