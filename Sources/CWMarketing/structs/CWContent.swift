//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 03.11.2022.
//

import Foundation

public struct CWContent: Codable {
    var _id: String
    public var name: String
    public var type: String?
    public var image: String?
    public var url: String?
    public var text: String?
    public var order: Int64?
    public var conceptId: String?
    public var createdAt: String
    public var updatedAt: String
    public var uiSettings: CWContentUISettings
}

public struct CWContentUISettings: Codable {
    public var url: String?
    public var text: String?
    public var color: String?
}

struct CWContentResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWContent]?
    var detail: String?
}

