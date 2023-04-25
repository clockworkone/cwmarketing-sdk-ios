//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 25.04.2023.
//

import Foundation

public struct CWOnlinePayment: Codable {
    public var orderId: String
    public var formUrl: String
}

public struct CWOnlinePaymentResponse: Codable {
    public var onlinePayment: CWOnlinePayment
}

public struct CWOnlinePaymentRequest: Codable {
    public var id: String
}
