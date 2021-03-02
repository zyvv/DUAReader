//
//  DUAConfig.swift
//  DUAReader
//
//  Created by mengminduan on 2017/12/26.
//  Copyright © 2017年 nothot. All rights reserved.
//

import UIKit
import Async
import Defaults

enum DUAReaderScrollType: Int {
    case curl
    case horizontal
    case vertical
    case none
}

class DUAConfiguration: NSObject {

    var contentFrame: CGRect = .zero
    
    var contentEdge: UIEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15) {
        didSet {
            Async.main {
                let width = screenWidth - self.contentEdge.left - self.contentEdge.right
                let height = screenHeight - UIScreen.topSpacing - UIScreen.bottomSpacing - self.contentEdge.top - self.contentEdge.bottom
                self.contentFrame = CGRect(origin: .zero, size: CGSize(width: width, height: height))
            }
        }
    }
    var lineHeightMutiplier: CGFloat = 2 {
        didSet {
            self.didLineHeightChanged(lineHeightMutiplier)
        }
    }
    var fontSize: CGFloat = 15 {
        didSet {
            self.didFontSizeChanged(fontSize)
        }
    }
    var fontName:String! {
        didSet {
            self.didFontNameChanged(fontName)
        }
    }
    var backgroundImage:UIImage! {
        didSet {
            self.didBackgroundImageChanged(backgroundImage)
        }
    }
    
    var scrollType = DUAReaderScrollType.curl {
        didSet {
            self.didScrollTypeChanged(scrollType)
        }
    }
    
    var didFontSizeChanged: (CGFloat) -> Void = {_ in }
    var didFontNameChanged: (String) -> Void = {_ in }
    var didBackgroundImageChanged: (UIImage) -> Void = {_ in }
    var didLineHeightChanged: (CGFloat) -> Void = {_ in }
    var didScrollTypeChanged: (DUAReaderScrollType) -> Void = {_ in }

    
    override init() {
        super.init()
        let font = UIFont.systemFont(ofSize: self.fontSize)
        self.fontName = font.fontName
//        let safeAreaTopHeight: CGFloat = UIScreen.main.bounds.size.height == 812.0 ? 24 : 0
//        let safeAreaBottomHeight: CGFloat = UIScreen.main.bounds.size.height == 812.0 ? 34 : 0
//        self.contentFrame = CGRect(x: 30, y: 30 + safeAreaTopHeight, width: UIScreen.main.bounds.size.width - 60, height: UIScreen.main.bounds.size.height - 60.0 - safeAreaTopHeight - safeAreaBottomHeight)
        
        
    }
    
}

struct Setting {

    enum ReaderScrollType: String, Codable {
        case curl = "curl"
        case horizontal = "horizontal"
        case vertical = "vertical"
        case none = "none"
    }
    
    enum ReaderContentInsetType: String, Codable {
        case large = "InsetLarge"
        case middle = "InsetMiddle"
        case small = "InsetSmall"
    }
    
    static var readerFontSize: Int {
        get { return Defaults[.readerFontSize] }
        set { Defaults[.readerFontSize] = newValue }
    }
    
    static var readerContentInsetType: ReaderContentInsetType {
        get { return Defaults[.readerContentInsetType] }
        set { Defaults[.readerContentInsetType] = newValue }
    }
    
    static var readerScrollType: ReaderScrollType {
        get { return Defaults[.readerScrollType] }
        set { Defaults[.readerScrollType] = newValue }
    }
    
    static var readerContentBounds: CGRect = CGRect(x: 0, y: 0, width: screenWidth - 30, height: screenHeight - 30)
}


extension Defaults.Keys {
    static let readerScrollType = Key<Setting.ReaderScrollType>("ReaderScrollType", default: .horizontal)
    static let readerContentInsetType = Key<Setting.ReaderContentInsetType>("ReaderContentInsetType", default: .middle)
    static let readerFontSize = Key<Int>("ReaderFontSize", default: 20)
}


extension UIScreen {
    static var topSpacing: CGFloat {
        
        let window = UIApplication.shared.keyWindow
        let topPadding = window?.safeAreaInsets.top
        return (topPadding ?? 0) + UIApplication.shared.statusBarFrame.height
    }
    
    static var bottomSpacing: CGFloat {
        let window = UIApplication.shared.keyWindow
        return window?.safeAreaInsets.bottom ?? 0
    }
}
