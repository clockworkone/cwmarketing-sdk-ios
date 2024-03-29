//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 20.09.2022.
//

import Foundation

public struct CWTerminal: Codable {
    public var _id: String
    public var address: String
    public var city: String
    public var timezone: String
    public var delivery: String?
    public var conceptId: String
    var order: Int64?
    var groupId: String
    var companyId: String
    var source: String?
    var geojson: String?
}

struct CWTerminalRequest: Codable {
    var limit: Int64?
    var page: Int64?
    var terminalId: String?
    var conceptId: String?
}

struct CWTerminalResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWTerminal]?
    var detail: String?
}
