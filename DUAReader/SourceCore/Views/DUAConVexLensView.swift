//
//  DUAConVexLensView.swift
//  DUAReader
//
//  Created by mengminduan on 2018/1/18.
//  Copyright © 2018年 nothot. All rights reserved.
//

import UIKit

class DUAConVexLensView: UIWindow {
    
    var locatePoint: CGPoint = CGPoint() {
        didSet {
            self.center = CGPoint(x: locatePoint.x, y: locatePoint.y - 5)
            self.setNeedsDisplay()
        }
    }
    
    var targetWindow: UIWindow?
    
    init(targetWindow: UIWindow?) {
        self.targetWindow = targetWindow
        super.init(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        
        self.layer.borderWidth = 3
        self.layer.borderColor = UIColor.lightGray.cgColor
        self.layer.cornerRadius = 50
        self.layer.masksToBounds = true
        
        self.windowLevel = UIWindowLevel(1.0)
        self.makeKeyAndVisible()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {

        let ctx = UIGraphicsGetCurrentContext()

        ctx?.translateBy(x: self.frame.width/2, y: self.frame.height/2)
        ctx?.scaleBy(x: 1.5, y: 1.5)
        ctx?.translateBy(x: -1 * locatePoint.x, y: -1 * (locatePoint.y + 60))
        targetWindow?.layer.render(in: ctx!)
    }

}
