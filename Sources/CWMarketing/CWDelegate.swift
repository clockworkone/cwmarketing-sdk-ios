//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 20.09.2022.
//

import Foundation

protocol CWDelegate: AnyObject {
    
    func addToCart(product: CWProduct)
    func removeFromCart(product: CWProduct)
    func wipeCart()
    func removeEntireFromCart(product: CWProduct)
    func totalDidUpdate(total: Float)
    
}

extension CWDelegate {
    func wipeCart() {}
    func removeEntireFromCart(product: CWProduct) {}
    func totalDidUpdate(total: Float) {}
}
