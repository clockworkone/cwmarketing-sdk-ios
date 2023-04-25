//
//  CWAuth.swift
//  
//
//  Created by Clockwork, LLC on 26.09.2022.
//

import Foundation

struct CWAuthRequest: Codable {
    var phone: Int64
    var code: String?
}

public struct CWAuthResponse: Codable {
    public var access_token: String?
    public var detail: CWDetail?
}

public struct CWCodeReponse: Codable {
    public var message: String
    public var isRegistered: Bool
    public var detail: CWDetail?
}
