//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 07.11.2022.
//

import Foundation

public struct CWAddress: Codable {
    var _id: String
    public var id: UUID
    public var city: String
    public var street: String
    public var home: String
    public var flat: Int64?
    public var floor: Int64?
    public var entrance: Int64?
    public var lat: Float?
    public var lon: Float?
    
    
    public init() {
        self._id = ""
        self.id = UUID()
        self.city = ""
        self.street = ""
        self.home = ""
    }
    
    public init(city: String, street: String, home: String, flat: Int64? = nil, floor: Int64? = nil, entrance: Int64? = nil, lat: Float? = nil, lon: Float? = nil) {
        self._id = ""
        self.id = UUID()
        self.city = city
        self.street = street
        self.home = home
        self.flat = flat
        self.floor = floor
        self.entrance = entrance
        self.lat = lat
        self.lon = lon
    }
    
    public init(_id: String, id: UUID, city: String, street: String, home: String, flat: Int64? = nil, floor: Int64? = nil, entrance: Int64? = nil, lat: Float? = nil, lon: Float? = nil) {
        self._id = _id
        self.id = id
        self.city = city
        self.street = street
        self.home = home
        self.flat = flat
        self.floor = floor
        self.entrance = entrance
        self.lat = lat
        self.lon = lon
    }
}
