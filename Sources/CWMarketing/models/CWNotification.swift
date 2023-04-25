//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 03.11.2022.
//

import Foundation

public struct CWNotification: Codable {
    public var _id: String
    public var title: String
    public var subtitle: String
    public var body: String
    public var image: CWImage?
    public var createdAt: String
    public var updatedAt: String
}

struct CWNotificationResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWNotification]?
    var detail: String?
}
