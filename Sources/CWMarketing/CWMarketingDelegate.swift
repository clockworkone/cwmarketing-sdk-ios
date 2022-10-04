//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 20.09.2022.
//

import Foundation

public protocol CWMarketingDelegate: AnyObject {
    
    func addToCart(product: CWProduct)
    func removeFromCart(product: CWProduct)
    func wipeCart()
    func removeEntireFromCart(product: CWProduct)
    func totalDidUpdate(total: Float)
    
}

extension CWMarketingDelegate {
    public func wipeCart() {}
    public func removeEntireFromCart(product: CWProduct) {}
    public func totalDidUpdate(total: Float) {}
}
