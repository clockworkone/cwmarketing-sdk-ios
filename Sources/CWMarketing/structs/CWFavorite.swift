//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 26.09.2022.
//

import Foundation

struct CWFavoriteRequest: Codable {
    var conceptId: String
    var productCode: String?
    var limit: Int64?
    var page: Int64?
    var isHidden: Bool?
    var isDisabled: Bool?
    var isDeleted: Bool?
}
