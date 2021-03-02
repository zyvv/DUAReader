//
//  UIView+subScript.swift
//  DUAReader
//
//  Created by mengminduan on 2017/12/27.
//  Copyright © 2017年 nothot. All rights reserved.
//

import UIKit
import CoreText

extension UIView {

    public var x: CGFloat{
        get{
            return self.frame.origin.x
        }
        set{
            var r = self.frame
            r.origin.x = newValue
            self.frame = r
        }
    }
    
    public var y: CGFloat{
        get{
            return self.frame.origin.y
        }
        set{
            var r = self.frame
            r.origin.y = newValue
            self.frame = r
        }
    }
    
    public var width: CGFloat{
        get{
            return self.frame.size.width
        }
        set{
            var r = self.frame
            r.size.width = newValue
            self.frame = r
        }
    }
    public var height: CGFloat{
        get{
            return self.frame.size.height
        }
        set{
            var r = self.frame
            r.size.height = newValue
            self.frame = r
        }
    }
    
    
    public var origin: CGPoint{
        get{
            return self.frame.origin
        }
        set{
            self.x = newValue.x
            self.y = newValue.y
        }
    }
    
    public var size: CGSize{
        get{
            return self.frame.size
        }
        set{
            self.width = newValue.width
            self.height = newValue.height
        }
    }
    
    public var centerX : CGFloat{
        get{
            return self.center.x
        }
        set{
            self.center = CGPoint(x: newValue, y: self.center.y)
        }
    }
    
    public var centerY : CGFloat{
        get{
            return self.center.y
        }
        set{
            self.center = CGPoint(x: self.center.x, y: newValue)
        }
    }
    
    public var rightX: CGFloat{
        get{
            return self.x + self.width
        }
        set{
            var r = self.frame
            r.origin.x = newValue - frame.size.width
            self.frame = r
        }
    }
    
    public var bottomY: CGFloat{
        get{
            return self.y + self.height
        }
        set{
            var r = self.frame
            r.origin.y = newValue - frame.size.height
            self.frame = r
        }
    }

}

extension NSAttributedString {
    func paging(with bounds: CGRect) -> [NSAttributedString] {
        let mutableSelf = NSMutableAttributedString(attributedString: self)
        var pagingStrings: [NSAttributedString] = []
        while mutableSelf.length > 0 {
            let path = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
            let frameSetter = CTFramesetterCreateWithAttributedString(mutableSelf)
            let frame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, mutableSelf.length), path, nil)
            let visibleStringRange = CTFrameGetVisibleStringRange(frame)
            pagingStrings.append(mutableSelf.attributedSubstring(from: NSRange(location: 0, length: visibleStringRange.length)))
            mutableSelf.deleteCharacters(in: NSRange(location: 0, length: visibleStringRange.length))
        }
        return pagingStrings
    }
    
    func paging(with bounds: CGRect, range: NSRange) -> NSAttributedString? {
        if self.length > 0 {
            let path = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
            let frameSetter = CTFramesetterCreateWithAttributedString(self)
            let frame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(range.location, range.length), path, nil)
            let visibleStringRange = CTFrameGetVisibleStringRange(frame)
            
            return self.attributedSubstring(from: NSRange(location: 0, length: visibleStringRange.length))
        }
        return nil
    }
}
