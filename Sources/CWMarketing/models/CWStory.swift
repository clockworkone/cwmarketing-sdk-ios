//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 19.08.2022.
//

import Foundation

public struct CWStory: Codable, Equatable {
    
    public static func == (lhs: CWStory, rhs: CWStory) -> Bool {
        return lhs._id == rhs._id
    }
    
    public var _id: String
    public var type: Int64
    var isDisabled: Bool?
    var isDeleted: Bool?
    var order: Int64
    public var name: String?
    public var title: String?
    public var subtitle: String?
    public var preview: CWImage
    public var slides: [CWImage]
}

public struct CWImage: Codable {
    public var body: String
    public var hash: String?
}

public struct CWStoryRequest: Codable {
    var conceptId: String?
    var limit: Int64?
    var page: Int64?
}

public struct CWStoryResponse: Codable {
    var limit: Int64?
    var page: Int64?
    var pages: Int64?
    var count: Int64?
    var data: [CWStory]?
    var detail: String?
}
