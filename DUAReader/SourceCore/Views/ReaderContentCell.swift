//
//  ReaderContentCell.swift
//  DUAReader
//
//  Created by 张洋威 on 2021/2/28.
//  Copyright © 2021 nothot. All rights reserved.
//

import UIKit
import SnapKit
import DTCoreText

class ReaderContentCell: UICollectionViewCell {
    var pageModel: DUAPageModel? {
        didSet {
            setNeedsLayout()
        }
    }
    
    let contentLabel: DTAttributedLabel = {
       let label = DTAttributedLabel()
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(contentLabel)
        contentLabel.snp.makeConstraints {
            $0.width.equalTo(Setting.readerContentBounds.width)
            $0.centerX.equalToSuperview()
            $0.top.bottom.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        contentLabel.attributedString = pageModel?.attributedString
    }
}
