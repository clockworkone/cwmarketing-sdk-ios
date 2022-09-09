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
    
    var _id: String
    var type: Int64
    var isDisabled: Bool?
    var isDeleted: Bool?
    var order: Int64
    var name: String?
    var title: String?
    var subtitle: String?
    var preview: CWImage
    var slides: [CWImage]
}

public struct CWImage: Codable {
    var body: String
    var hash: String?
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
