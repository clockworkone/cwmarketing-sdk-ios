//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 21.09.2022.
//

import Foundation

@propertyWrapper
public struct SkipCodable<T>: Codable {
    public var wrappedValue: T?
        
    public init(wrappedValue: T?) {
        self.wrappedValue = wrappedValue
    }
    
    public init(from decoder: Decoder) throws {
        self.wrappedValue = nil
    }
    
    public func encode(to encoder: Encoder) throws {
        // Do nothing
    }
}

extension KeyedDecodingContainer {
    public func decode<T>(_ type: SkipCodable<T>.Type, forKey key: Self.Key) throws -> SkipCodable<T> {
        return SkipCodable(wrappedValue: nil)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<T>(_ value: SkipCodable<T>, forKey key: KeyedEncodingContainer<K>.Key) throws {
        // Do nothing
    }
}
