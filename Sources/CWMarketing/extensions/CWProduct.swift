//
//  File.swift
//  
//
//  Created by Clockwork, LLC on 20.09.2022.
//

import Foundation

extension CWProduct {
    
    func getPrice() -> UInt {
        if self.weight.min > 0 {
            return UInt(self.weight.min * self.price)
        }
        
        return UInt(self.price)
    }
    
    func getPrice() -> Float {
        if self.weight.min > 0 {
            return self.weight.min * self.price
        }
        
        return self.price
    }
    
    func getWeight() -> Float {
        if self.weight.min > 0 {
            return self.weight.min
        }
        
        return self.weight.full
    }
    
    func getPriceWithModifiers() -> UInt {
        var total: Float = 0.0
        let weight = self.getWeight()
        
        var modifiersPrice: Float = 0
        if let modifiers = self.orderModifiers {
            for modifier in modifiers {
                for option in modifier.options {
                    modifiersPrice += option.price * weight
                }
            }
        }
        
        total += (self.getPrice() + modifiersPrice) * self.count
        return UInt(total)
    }
    
    func getPriceWithModifiers() -> Float {
        var total: Float = 0.0
        let weight = self.getWeight()
        
        var modifiersPrice: Float = 0
        if let modifiers = self.orderModifiers {
            for modifier in modifiers {
                for option in modifier.options {
                    modifiersPrice += option.price * weight
                }
            }
        }
        
        total += (self.getPrice() + modifiersPrice) * self.count
        return total
    }
    
}
