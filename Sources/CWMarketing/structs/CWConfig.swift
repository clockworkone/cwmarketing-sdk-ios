//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 18.08.2022.
//

import Foundation

public struct CWConfig {
    var apiKey: String
    var loyaltyId: String
    var companyId: String
    var timeout: Int64?
    var version: String?
    var defaultLimitPerPage: Int64
    var source: String?
    var cacheRules: CWConfigImageCache?
    
    init() {
        self.apiKey = ""
        self.loyaltyId = ""
        self.companyId = ""
        self.defaultLimitPerPage = 25
    }
    
    public init(apiKey: String, loyaltyId: String, companyId: String, defaultLimitPerPage: Int64 = 25, source: String? = nil, cacheRules: CWConfigImageCache = CWConfigImageCache()) {
        self.apiKey = apiKey
        self.loyaltyId = loyaltyId
        self.companyId = companyId
        self.defaultLimitPerPage = defaultLimitPerPage
        self.cacheRules = cacheRules
        self.source = source
    }
}

public struct CWConfigImageCache {
    var memoryCapacity: UInt64
    var diskCapacity: Int
    var usageAfterPurge: UInt64
    
    public init(memoryCapacity: UInt64 = 100 * 1024 * 1024, diskCapacity: Int = 250 * 1024 * 1024, usageAfterPurge: UInt64 = 25 * 1024 * 1024) {
        self.memoryCapacity = memoryCapacity
        self.diskCapacity = diskCapacity
        self.usageAfterPurge = usageAfterPurge
    }
}
