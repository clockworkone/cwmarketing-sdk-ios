//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 20.09.2022.
//

import Foundation

public struct CWTerminal: Codable {
    public var _id: String
    var externalId: String?
    var organization: String?
    var address: String
    var city: String
    var timezone: String
    var delivery: String?
}

struct CWTerminalRequest: Codable {
    var limit: Int64?
    var page: Int64?
    var terminalId: String?
}

struct CWTerminalResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWTerminal]?
    var detail: String?
}
