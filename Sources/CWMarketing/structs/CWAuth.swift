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



public struct CWCodeReponse: Codable {
    var message: String
    var isRegistered: Bool
    var detail: CWDetail?
}
