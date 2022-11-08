//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 08.11.2022.
//

import Foundation

extension Bundle {
    
    var releaseVersion: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    var buildVersion: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
    
}
