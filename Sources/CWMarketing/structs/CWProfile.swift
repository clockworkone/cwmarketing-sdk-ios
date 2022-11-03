//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 02.11.2022.
//

import Foundation

public struct CWProfile: Codable {
    var _id: String
    public var firstName: String
    public var lastName: String
    public var phone: Int64
    public var email: String?
    public var sex: String?
    public var dob: String?
    public var card: Int64
    public var externalId: String?
    public var wallet: CWWallet
    public var favoriteProducts: [String]?
    public var balances: CWBalances
    public var detail: String?
}

public struct CWWallet: Codable {
    var auth: String?
    public var card: String?
}

public struct CWBalances: Codable {
    public var total: Float
    public var categories: [String]
    public var balances: [CWBalance]
}

public struct CWBalance: Codable {
    public var balance: Float
    public var wallet: String
}

struct CWProfileResponse: Codable {
    var detail: String?
}
