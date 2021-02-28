//
//  ReaderContentCell.swift
//  DUAReader
//
//  Created by 张洋威 on 2021/2/28.
//  Copyright © 2021 nothot. All rights reserved.
//

import UIKit
import YYText
import SnapKit

class ReaderContentCell: UICollectionViewCell {
    var pageModel: DUAPageModel? {
        didSet {
            setNeedsLayout()
        }
    }
    
    let contentTextView: YYTextView = {
       let textView = YYTextView()
        textView.isEditable = false
        return textView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(contentTextView)
        contentTextView.contentInset = UIEdgeInsets(top: 15, left: 15, bottom: -15, right: -15)
        contentTextView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
        contentTextView.backgroundColor = .orange
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        contentTextView.attributedText = pageModel?.attributedString
    }
}
