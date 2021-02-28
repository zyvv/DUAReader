//
//  PageViewModel.swift
//  DUAReader
//
//  Created by 张洋威 on 2021/2/28.
//  Copyright © 2021 nothot. All rights reserved.
//

import Foundation
import UIKit
import YYText

struct PageViewModel {
    
    internal init(textLayout: YYTextLayout, model: DUAPageModel) {
        self.textLayout = textLayout
        self.model = model
        textLayout.visibleRange
    }
    
    var textLayout: YYTextLayout
    var model: DUAPageModel
    
    
    
}
