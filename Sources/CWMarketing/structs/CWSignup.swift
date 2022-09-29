//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 29.09.2022.
//

import Foundation

public struct CWSignup: Codable {
    
}

public struct CWSignupRequest: Codable {
    public var firstName: String
    public var lastName: String
    public var email: String
    public var sex: CWSex
    public var dob: Date
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try container.encode(email, forKey: .email)
        
        var curentSex = "notSpecified"
        switch sex {
        case .male:
            curentSex = "male"
        case .female:
            curentSex = "female"
        default:
            curentSex = "notSpecified"
        }
        try container.encode(curentSex, forKey: .sex)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dobString = formatter.string(from: dob)
        try container.encode(dobString, forKey: .dob)
    }
    
    public init(firstName: String, lastName: String, email: String, sex: CWSex, dob: Date) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.sex = sex
        self.dob = dob
    }
    
}

public struct CWSignupResponse: Codable {
    public var isRegistered: Bool
    public var balance: Float?
    public var appleWallet: String?
    public var googleWallet: String?
    public var detail: CWDetail?
}
