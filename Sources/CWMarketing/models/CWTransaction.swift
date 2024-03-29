//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 01.09.2023.
//

import Foundation

public struct CWTransaction: Codable {
    var _id: String
    public var sum: Float
    var changedOn: String
    var conceptId: String?
    var source: String
    var createdAt: String
    public var concept: CWConcept?
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encode(sum, forKey: .sum)
        try container.encode(conceptId, forKey: .conceptId)
        try container.encode(concept, forKey: .concept)
        try container.encode(source, forKey: .source)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(changedOn, forKey: .changedOn)
    }
}

struct CWTransactionRequest: Codable {
    var limit: Int64?
    var page: Int64?
    var conceptId: String?
}

struct CWTransactionResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWTransaction]?
    var detail: String?
}

extension CWTransaction {
    
    public mutating func changedOn(_ format: String = "dd.MM.YYYY HH:mm") -> String {
        let dateWithoutMicroseconds = changedOn.components(separatedBy: ".")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.init(abbreviation: "UTC")
        if let date = dateFormatter.date(from: dateWithoutMicroseconds[0]) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = format
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.locale = Locale(identifier: "ru")
            return dateFormatter.string(from: date)
        }
        
        return ""
    }
    
}
