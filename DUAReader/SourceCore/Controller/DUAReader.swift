//
//  DUAReader.swift
//  DUAReader
//
//  Created by mengminduan on 2017/12/26.
//  Copyright © 2017年 nothot. All rights reserved.
//

import UIKit
import DTCoreText

enum DUAReaderState {
    case busy
    case ready
}

protocol DUAReaderDelegate: NSObjectProtocol {
    func readerDidClickSettingFrame(reader: DUAReader) -> Void
    func reader(reader: DUAReader, readerStateChanged state: DUAReaderState) -> Void
    func reader(reader: DUAReader, readerProgressUpdated curChapter: Int, curPage: Int, totalPages: Int) -> Void
    func reader(reader: DUAReader, chapterTitles: [String]) -> Void
    
}

class DUAReader: UIViewController, UIPageViewControllerDelegate, UIPageViewControllerDataSource, UIGestureRecognizerDelegate, UITableViewDataSource, UITableViewDelegate, DUATranslationProtocol {
    /// 配置类
    public var config: DUAConfiguration!
    /// 代理
    public var delegate: DUAReaderDelegate?
    /// 章节缓存（分页后的页面数组）
    private var chapterCaches: [String: [DUAPageModel]] = [String: [DUAPageModel]]()
    /// chapter model cache
    private var chapterModels = [String: DUAChapterModel]()
    /// 数据解析类
    private var dataParser: DUATextDataParser = DUATextDataParser()
    /// 缓存队列
    private var cacheQueue: DispatchQueue = DispatchQueue(label: "duareader.cache.queue")
    /// page vc
    private var pageVC: DUAContainerPageViewController?
    /// table view
    private var tableView: DUATableView?
    /// translation vc
    private var translationVC: DUAtranslationControllerExt?

    private var collectionView: UICollectionView?
    
    private var currentChapterDataSource: [DUAPageModel] = []
    
    /// 状态栏
    private var statusBar: DUAStatusBar?
    /// 是否重分页
    private var isReCutPage: Bool = false
    /// 当前页面
    private var currentPageIndex: Int = 1
    /// 当前章节
    private var currentChapterIndex: Int = 0
    /// 分页前当前页首字符索引
    
    /// 重分页后如何定位阅读进度？
    /// 首先记录分页前当前页面首字符在本章的索引，重分页后根据索引确定用户先前看的页面在章节中新的位置
    private var prePageStartLocation: Int = -1
    /// 首次进阅读器
    private var firstIntoReader = true
    /// 页面饥饿
    private var pageHunger = false
    /// 解析后的所有章节model
    private var totalChapterModels: [DUAChapterModel] = []
    /// 对table view而言，status bar是放在reader view上的，其他模式则是放在每个page页面上
    private var statusBarForTableView: DUAStatusBar?
    /// 是否成功切换到某章节，成功为0，不成功则记录未成功切换的章节index，当指定跳至某章节时使用
    var successSwitchChapter = 0
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK:--对外接口
    public func readWith(filePath: String, pageIndex: Int) -> Void {
        
        self.postReaderStateNotification(state: .busy)
        self.dataParser.parseChapterFromBook(path: filePath, completeHandler: {(titles, models) -> Void in
            if self.delegate?.reader(reader: chapterTitles: ) != nil {
                self.delegate?.reader(reader: self, chapterTitles: titles)
            }
            self.totalChapterModels = models
            if models.count > 0 {
                self.readWith(chapter: models.first!, pageIndex: pageIndex)
            }
        })
        
    }
    
    public func readChapterBy(index: Int, pageIndex: Int) -> Void {
        if index > 0 && index <= totalChapterModels.count {
            if self.pageArrayFromCache(chapterIndex: index).isEmpty {
                successSwitchChapter = index
                self.postReaderStateNotification(state: .busy)
                self.requestChapterWith(index: index)
            }else {
                successSwitchChapter = 0
                currentPageIndex = pageIndex <= 0 ? 0 : (pageIndex - 1)
                self.updateChapterIndex(index: index)
                self.loadPage(pageIndex: currentPageIndex)
                if self.delegate?.reader(reader: readerProgressUpdated: curPage: totalPages: ) != nil {
                    self.delegate?.reader(reader: self, readerProgressUpdated: currentChapterIndex, curPage: currentPageIndex + 1, totalPages: self.pageArrayFromCache(chapterIndex: currentChapterIndex).count)
                }
            }
        }
    }
    
    // MARK:-- 以下为私有方法
    private func readWith(chapter: DUAChapterModel, pageIndex: Int) -> Void {
        
        chapterModels[String(chapter.chapterIndex)] = chapter
        if Thread.isMainThread == false {
            self.forwardCacheWith(chapter: chapter)
            return
        }
        
        var pageModels: [DUAPageModel] = [DUAPageModel]()
        if self.isReCutPage {
            self.postReaderStateNotification(state: .busy)
            self.chapterCaches.removeAll()
        }else {
            pageModels = self.pageArrayFromCache(chapterIndex: chapter.chapterIndex)
        }
        if pageModels.isEmpty || self.isReCutPage {
            self.cacheQueue.async {
                if self.pageArrayFromCache(chapterIndex: chapter.chapterIndex).isEmpty == false {
                    return
                }
                guard let attrString = self.dataParser.attributedStringFromChapterModel(chapter: chapter, config: self.config) else { return }
                self.dataParser.cutPageWith(attrString: attrString, config: self.config, completeHandler: {
                    (completedPageCounts, page, completed) -> Void in
                    pageModels.append(page)
                    if completed {
                        self.cachePageArray(pageModels: pageModels, chapterIndex: chapter.chapterIndex)
                        DispatchQueue.main.async {
                            self.processPageArray(pages: pageModels, chapter: chapter, pageIndex: pageIndex)
                        }
                        
                    }
                })
            }
        }
        
        
    }
    
    private func processPageArray(pages: [DUAPageModel], chapter: DUAChapterModel, pageIndex: Int) -> Void {
        
        self.postReaderStateNotification(state: .ready)
        if pageHunger {
            pageHunger = false
            if pageVC != nil {
                self.loadPage(pageIndex: currentPageIndex)
            }
            if tableView != nil {
                if currentPageIndex == 0 && tableView?.scrollDirection == .up {
                    self.requestLastChapterForTableView()
                }
                if currentPageIndex == self.pageArrayFromCache(chapterIndex: currentChapterIndex).count - 1 && tableView?.scrollDirection == .down {
                    self.requestNextChapterForTableView()
                }
            }
        }
        
        if firstIntoReader {
            firstIntoReader = false
            currentPageIndex = pageIndex <= 0 ? 0 : (pageIndex - 1)
            updateChapterIndex(index: chapter.chapterIndex)
            self.loadPage(pageIndex: currentPageIndex)
            if self.delegate?.reader(reader: readerProgressUpdated: curPage: totalPages: ) != nil {
                self.delegate?.reader(reader: self, readerProgressUpdated: currentChapterIndex, curPage: currentPageIndex + 1, totalPages: self.pageArrayFromCache(chapterIndex: currentChapterIndex).count)
            }
        }
        
        if isReCutPage {
            isReCutPage = false
            var newIndex = 1
            for (index, item) in pages.enumerated() {
                if prePageStartLocation >= (item.range?.location ?? 0) && prePageStartLocation <= (item.range?.location ?? 0) + (item.range?.length ?? 0) {
                    newIndex = index
                }
            }
            currentPageIndex = newIndex
            self.loadPage(pageIndex: currentPageIndex)
            
            /// 触发预缓存
            self.forwardCacheIfNeed(forward: true)
            self.forwardCacheIfNeed(forward: false)
        }
        
        if successSwitchChapter != 0 {
            self.readChapterBy(index: successSwitchChapter, pageIndex: 1)
        }
    }
    
    private func postReaderStateNotification(state: DUAReaderState) -> Void {
        DispatchQueue.main.async {
            if self.delegate?.reader(reader: readerStateChanged: ) != nil {
                self.delegate?.reader(reader: self, readerStateChanged: state)
            }
        }
    }
    
    /// 弹出设置菜单
    ///
    /// - Parameter ges: 单击手势
    @objc private func pagingTap(ges: UITapGestureRecognizer) -> Void {
        let tapPoint = ges.location(in: self.view)
        let width = UIScreen.main.bounds.size.width
        let rect = CGRect(x: width/3, y: 0, width: width/3, height: UIScreen.main.bounds.size.height)
        if rect.contains(tapPoint) {
            if self.delegate?.readerDidClickSettingFrame(reader:) != nil {
                self.delegate?.readerDidClickSettingFrame(reader: self)
            }
        }
    }
    
    // MARK:--UI渲染
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.white
        let tapGesture = UITapGestureRecognizer.init(target: self, action: #selector(pagingTap(ges:)))
        self.view.addGestureRecognizer(tapGesture)
        self.addObserverForConfiguration()
        self.loadReaderView()
    }
    
    private func loadReaderView() -> Void {
        switch self.config.scrollType {
        case .curl:
            self.loadPageViewController()
        case .vertical:
            self.loadTableView(scrollDirection: .vertical)
        case .horizontal:
            self.loadTranslationVC(animating: true)
        case .none:
            self.loadTranslationVC(animating: false)
        }
        
        if self.config.backgroundImage != nil {
            self.loadBackgroundImage()
        }
    }
    
    private func loadPageViewController() -> Void {

        self.clearReaderViewIfNeed()
        let transtionStyle: UIPageViewControllerTransitionStyle = (self.config.scrollType == .curl) ? .pageCurl : .scroll
        let pageVC = DUAContainerPageViewController(transitionStyle: transtionStyle, navigationOrientation: .horizontal, options: nil)
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.view.backgroundColor = UIColor.clear
        pageVC.isDoubleSided = (self.config.scrollType == .curl) ? true : false

        self.addChildViewController(pageVC)
        self.view.addSubview(pageVC.view)
        pageVC.didMove(toParentViewController: self)
        self.pageVC = pageVC
    }
    
    private func loadTableView(scrollDirection: UICollectionViewScrollDirection) -> Void {
        
        self.clearReaderViewIfNeed()
        
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = scrollDirection
        layout.minimumLineSpacing = 0
        layout.sectionInset = .zero
        layout.itemSize = CGSize(width: screenWidth, height: screenHeight)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView?.showsVerticalScrollIndicator = false
        collectionView?.showsHorizontalScrollIndicator = false
//        collectionView?.isPagingEnabled = true
        collectionView?.delegate = self
        collectionView?.dataSource = self
        collectionView?.backgroundColor = .clear
        collectionView?.register(ReaderContentCell.self, forCellWithReuseIdentifier: "ReaderContentCell")
        view.addSubview(collectionView!)
        collectionView?.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
        
//        let tableView = DUATableView(frame: CGRect.init(x: 0, y: config.contentFrame.origin.y, width: UIScreen.main.bounds.size.width, height: config.contentFrame.size.height), style: .plain)
//        tableView.dataSource = self
//        tableView.delegate = self
//        tableView.showsVerticalScrollIndicator = false
//        tableView.separatorStyle = .none
//        tableView.estimatedRowHeight = 0
//        tableView.scrollsToTop = false
//        tableView.backgroundColor = UIColor.clear
//
//        self.view.addSubview(tableView)
//        self.tableView = tableView
        
        self.addStatusBarTo(view: self.view, totalCounts: self.pageArrayFromCache(chapterIndex: currentChapterIndex).count, curPage: currentPageIndex)
    }
    
    /// bool值意味着平移翻页还是无动画翻页
    ///
    /// - Parameter animating: none
    func loadTranslationVC(animating: Bool) -> Void {
        
        self.clearReaderViewIfNeed()
        let translationVC = DUAtranslationControllerExt()
        translationVC.delegate = self
        translationVC.allowAnimating = animating
        self.addChildViewController(translationVC)
        translationVC.didMove(toParentViewController: self)
        self.view.addSubview(translationVC.view)
        self.translationVC = translationVC
    }
    
    private func loadPage(pageIndex: Int) -> Void {
        switch self.config.scrollType {
        case .curl:
            let page = self.getPageVCWith(pageIndex: pageIndex, chapterIndex: self.currentChapterIndex)
            if page == nil {
                return
            }
            self.pageVC?.setViewControllers([page!], direction: .forward, animated: false, completion: nil)
        case .vertical:
            currentChapterDataSource.removeAll()
            currentChapterDataSource = self.pageArrayFromCache(chapterIndex: currentChapterIndex)
//            self.tableView?.cellIndex = pageIndex
//            if tableView?.dataArray == nil {
//                return
//            }
            
            collectionView?.reloadData()
            collectionView?.scrollToItem(at: IndexPath(item: pageIndex, section: 0), at: .top, animated: false)
            
//            self.statusBarForTableView?.totalPageCounts = (tableView?.dataArray.count) ?? 0
//            self.statusBarForTableView?.curPageIndex = currentPageIndex
            
            /// 当加载的页码为最后一页，需要手动触发一次下一章的请求
            if self.currentPageIndex == self.pageArrayFromCache(chapterIndex: self.currentChapterIndex).count - 1 {
                self.requestNextChapterForTableView()
            }
        case .horizontal:
            guard let page = self.getPageVCWith(pageIndex: pageIndex, chapterIndex: self.currentChapterIndex) else { return }
            self.translationVC?.setViewController(viewController: page, direction: .left, animated: false, completionHandler: nil)
        case .none:
            guard let page = self.getPageVCWith(pageIndex: pageIndex, chapterIndex: self.currentChapterIndex) else { return }
            self.translationVC?.setViewController(viewController: page, direction: .left, animated: false, completionHandler: nil)
            
        }
    }
    
    private func loadBackgroundImage() -> Void {
        if config.scrollType == .curl {
            if let curPage = pageVC?.viewControllers?.first as? DUAPageViewController {
                if let imageView = curPage.view.subviews.first as? UIImageView {
                    imageView.image = self.config.backgroundImage
                }
            }
        }
        
        if config.scrollType == .horizontal || config.scrollType == .none {
            if let curPage = translationVC?.childViewControllers.first as? DUAPageViewController {
                if let imageView = curPage.view.subviews.first as? UIImageView {
                    imageView.image = self.config.backgroundImage
                }
            }
            
            if let firstView = self.view.subviews.first as? UIImageView {
                firstView.image = self.config.backgroundImage
            } else {
                let imageView = UIImageView.init(frame: self.view.frame)
                imageView.image = self.config.backgroundImage
                self.view.insertSubview(imageView, at: 0)
            }
        }
    }
    
    private func addStatusBarTo(view: UIView, totalCounts: Int, curPage: Int) -> Void {
        let safeAreaBottomHeight: CGFloat = UIScreen.main.bounds.size.height == 812.0 ? 34 : 0
        let rect = CGRect(x: config.contentFrame.origin.x, y: UIScreen.main.bounds.size.height - 30 - safeAreaBottomHeight, width: config.contentFrame.width, height: 20)
        let statusBar = DUAStatusBar.init(frame: rect)
        view.addSubview(statusBar)
        statusBar.totalPageCounts = totalCounts
        statusBar.curPageIndex = curPage
        self.statusBarForTableView = statusBar
    }
    
    func clearReaderViewIfNeed() -> Void {
        self.pageVC?.view.removeFromSuperview()
        self.pageVC?.willMove(toParentViewController: nil)
        self.pageVC?.removeFromParentViewController()
        
        if self.tableView != nil {
            for item in self.view.subviews {
                item.removeFromSuperview()
            }
        }
        
        self.translationVC?.view.removeFromSuperview()
        self.translationVC?.willMove(toParentViewController: nil)
        self.translationVC?.removeFromParentViewController()
    }
    
    /// MARK:--数据处理
    
    
    /// 仿真、平移、无动画翻页模式使用
    ///
    /// - Parameters:
    ///   - pageIndex: 页面索引
    ///   - chapterIndex: 章节索引
    /// - Returns: 单个page页面
    private func getPageVCWith(pageIndex: Int, chapterIndex: Int) -> DUAPageViewController? {
 
        let dtLabel = DUAAttributedView.init(frame: CGRect(x: 0, y: config.contentFrame.origin.y, width: self.view.width, height: config.contentFrame.height))
        dtLabel.edgeInsets = UIEdgeInsets.init(top: 0, left: config.contentFrame.origin.x, bottom: 0, right: config.contentFrame.origin.x)
        
        let pageArray = self.pageArrayFromCache(chapterIndex: chapterIndex)
        if pageArray.isEmpty {
            return nil
        }
        var fixedPageIndex = pageIndex
        if fixedPageIndex == pageArray.count {
            print("-----出现错误了-----")
            fixedPageIndex -= 1
        }
        let pageModel = pageArray[fixedPageIndex]
        dtLabel.attributedString = pageModel.attributedString
        dtLabel.backgroundColor = UIColor.clear
        
        let page = DUAPageViewController()
        page.index = fixedPageIndex
        page.chapterBelong = chapterIndex
        if self.config.backgroundImage != nil {
            page.backgroundImage = self.config.backgroundImage
        }
        page.view.addSubview(dtLabel)
    
        self.addStatusBarTo(view: page.view, totalCounts: pageArray.count, curPage: pageIndex)
        
        return page
    }
    
    private func pageArrayFromCache(chapterIndex: Int) -> [DUAPageModel] {
        if let pageArray = self.chapterCaches[String(chapterIndex)] {
            return pageArray
        }else {
            return []
        }
    }
    
    private func cachePageArray(pageModels: [DUAPageModel], chapterIndex: Int) -> Void {
        self.chapterCaches[String(chapterIndex)] = pageModels
///     for item in self.chapterCaches.keys {
///         if Int(item)! - currentChapterIndex > 2 || Int(item)! - currentChapterIndex < -1 {
///             self.chapterCaches.removeValue(forKey: item)
///         }
///     }
    }
    
    
    private func requestChapterWith(index: Int) -> Void {
        if self.pageArrayFromCache(chapterIndex: index).isEmpty == false {
            return
        }
    
        /// 这里在书籍解析后直接保存了所有章节model，故直接取即可
        
        /// 对于分章节阅读的情况，每个章节可能需要通过网络请求获取，完成后调用readWithchapter方法即可
        
        let chapter = totalChapterModels[index - 1]
        self.readWith(chapter: chapter, pageIndex: 1)
    }
    
    private func updateChapterIndex(index: Int) -> Void {
        if currentChapterIndex == index {
            return
        }
        print("进入第 \(index) 章")
        let forward = currentChapterIndex > index ? false : true
        currentChapterIndex = index
        
        /// 每当章节切换时触发预缓存
        self.forwardCacheIfNeed(forward: forward)
    }
    
    
    /// 请求上个章节 for tableview
    private func requestLastChapterForTableView() -> Void {
        tableView?.scrollDirection = .up
        if currentChapterIndex - 1 <= 0 {
            return
        }
        self.requestChapterWith(index: currentChapterIndex - 1)
        let lastPages = self.pageArrayFromCache(chapterIndex: currentChapterIndex - 1)
        if lastPages.isEmpty {
            /// 页面饥饿
            pageHunger = true
            self.postReaderStateNotification(state: .busy)
            return
        }
        var indexPathsToInsert: [IndexPath] = []
        for (index, _) in lastPages.enumerated() {
            let indexPath = IndexPath(row: index, section: 0)
            indexPathsToInsert.append(indexPath)
        }
        self.tableView?.dataArray = lastPages + (self.tableView?.dataArray ?? [])
        self.tableView?.beginUpdates()
        self.tableView?.insertRows(at: indexPathsToInsert, with: .top)
        self.tableView?.endUpdates()

        DispatchQueue.main.async {
            self.tableView?.cellIndex += lastPages.count
            self.tableView?.setContentOffset(CGPoint.init(x: 0, y: CGFloat.init(lastPages.count)*self.config.contentFrame.height), animated: false)
        }
        
    }
    
    /// 请求下个章节 for tableview
    private func requestNextChapterForTableView() -> Void {
        tableView?.scrollDirection = .down
        if currentChapterIndex >= totalChapterModels.count {
            // 最后一个章节已经读完了
            return
        }
        self.requestChapterWith(index: currentChapterIndex + 1)
        let nextPages = self.pageArrayFromCache(chapterIndex: currentChapterIndex + 1)
        if nextPages.isEmpty {
            ///                 页面饥饿
            pageHunger = true
            self.postReaderStateNotification(state: .busy)
            return
        }
//        var indexPathsToInsert: [IndexPath] = []
//        for (index, _) in nextPages.enumerated() {
//            let indexPath = IndexPath(row: (tableView?.dataArray.count ?? 0) + index, section: 0)
//            indexPathsToInsert.append(indexPath)
//        }
//        self.tableView?.dataArray += nextPages
//        self.tableView?.beginUpdates()
//        self.tableView?.insertRows(at: indexPathsToInsert, with: .none)
//        self.tableView?.endUpdates()
        
        
        
        let fromItemIndex = currentChapterDataSource.count
        let insetItemIndexPaths = nextPages.enumerated().map { index, _ in
            IndexPath(item: index + fromItemIndex, section: 0)
        }
        
        currentChapterDataSource.append(contentsOf: nextPages)
        
        collectionView?.performBatchUpdates({
            collectionView?.insertItems(at: insetItemIndexPaths)
        }, completion: nil)
    }
    
    // MARK:--预缓存
    
    
    /// 为何要预缓存？
    /// 本阅读器是按照逐个章节的方式阅读的（便于分章阅读，例如连载小说等），如果当前章节阅读结束时请求下一章数据
    /// 那么章节解析分页均会耗时（当然你可以不等分页全部完成就直接展示已经分好的页面，以减少用户等待，那是另一套
    /// 逻辑了）。因此每当用户跨入新的一章，程序自动触发当前章下一章的请求，提前准备好数据，以实现章节无缝切换
    ///
    /// - Parameter forward: 向前缓存还是向后缓存
    private func forwardCacheIfNeed(forward: Bool) -> Void {
        let predictIndex = forward ? currentChapterIndex + 1 : currentChapterIndex - 1
        if predictIndex <= 0 || predictIndex > totalChapterModels.count {
            return
        }
        self.cacheQueue.async {
            let nextPageArray = self.pageArrayFromCache(chapterIndex: predictIndex)
            if nextPageArray.isEmpty {
                print("执行预缓存 章节 \(predictIndex)")
                self.requestChapterWith(index: predictIndex)
            }
        }
    }
    
    private func forwardCacheWith(chapter: DUAChapterModel) -> Void {
        var pageArray: [DUAPageModel] = []
        guard let attrString = self.dataParser.attributedStringFromChapterModel(chapter: chapter, config: self.config) else { return }
        self.dataParser.cutPageWith(attrString: attrString, config: self.config, completeHandler: {
            (completedPageCounts, page, completed) -> Void in
            pageArray.append(page)
            if completed {
                self.cachePageArray(pageModels: pageArray, chapterIndex: chapter.chapterIndex)
                print("预缓存完成")
                if pageHunger {
                    DispatchQueue.main.async {
                        self.postReaderStateNotification(state: .ready)
                        self.pageHunger = false
                        if self.pageVC != nil {
                            self.loadPage(pageIndex: self.currentPageIndex)
                        }
                        if self.tableView != nil {
                            if self.currentPageIndex == 0 && self.tableView?.scrollDirection == .up {
                                self.requestLastChapterForTableView()
                            }
                            if self.currentPageIndex == self.pageArrayFromCache(chapterIndex: self.currentChapterIndex).count - 1 && self.tableView?.scrollDirection == .down {
                                self.requestNextChapterForTableView()
                            }
                        }
                    }
                }
            }
        })
    }
    
    // MARK:--属性观察器
    
    private func addObserverForConfiguration() -> Void {
        self.config.didFontSizeChanged = {[weak self] (fontSize) in
            self?.reloadReader()
        }
        self.config.didLineHeightChanged = {[weak self] (lineHeight) in
            self?.reloadReader()
        }
        self.config.didFontNameChanged = {[weak self] (String) in
            self?.reloadReader()
        }
        self.config.didBackgroundImageChanged = {[weak self] (UIImage) in
            self?.loadBackgroundImage()
        }
        self.config.didScrollTypeChanged = {[weak self] (DUAReaderScrollType) in
            guard let self = self else { return }
            self.loadReaderView()
            self.loadPage(pageIndex: self.currentPageIndex)
        }
    }
    
    private func reloadReader() -> Void {
        isReCutPage = true
        if prePageStartLocation == -1 {
            let pageArray = self.pageArrayFromCache(chapterIndex: currentChapterIndex)
            prePageStartLocation = (pageArray[currentPageIndex].range?.location) ?? 0
        }
        if let chapter = chapterModels[String(currentChapterIndex)] {
            self.readWith(chapter: chapter, pageIndex: currentPageIndex)
        }
    }
    
    // MARK:--PageVC Delegate
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        print("向前翻页")
        struct FirstPage {
            static var arrived = false
        }
        if let page = viewController as? DUAPageViewController {
            let backPage = DUABackViewController()
            var nextIndex = page.index - 1
            if nextIndex < 0 {
                if currentChapterIndex <= 1 {
                    return nil
                }
                FirstPage.arrived = true
                self.pageVC?.willStepIntoLastChapter = true
                self.requestChapterWith(index: currentChapterIndex - 1)
                nextIndex = self.pageArrayFromCache(chapterIndex: currentChapterIndex - 1).count - 1
                let nextPage = self.getPageVCWith(pageIndex: nextIndex, chapterIndex: currentChapterIndex - 1)
                ///         需要的页面并没有准备好，此时出现页面饥饿
                if nextPage == nil {
                    self.postReaderStateNotification(state: .busy)
                    pageHunger = true
                    return nil
                }else {
                    backPage.grabViewController(viewController: nextPage!)
                    return backPage
                }
            }
            backPage.grabViewController(viewController: self.getPageVCWith(pageIndex: nextIndex, chapterIndex: page.chapterBelong)!)
            return backPage
        }
        if let back = viewController as? DUABackViewController {
            if FirstPage.arrived {
                FirstPage.arrived = false
            }
            return self.getPageVCWith(pageIndex: back.index, chapterIndex: back.chapterBelong)
        }
        return nil
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        print("向后翻页!!!!")
        struct LastPage {
            static var arrived = false
        }
        let nextIndex: Int
        let pageArray = self.pageArrayFromCache(chapterIndex: currentChapterIndex)
        if let page = viewController as? DUAPageViewController {
            nextIndex = page.index + 1
            if nextIndex == pageArray.count {
                LastPage.arrived = true
            }
            let backPage = DUABackViewController()
            backPage.grabViewController(viewController: page)
            return backPage
        }
        
        if LastPage.arrived {
            LastPage.arrived = false
            if currentChapterIndex + 1 > totalChapterModels.count {
                return nil
            }
            pageVC?.willStepIntoNextChapter = true
            self.requestChapterWith(index: currentChapterIndex + 1)
            let nextPage = self.getPageVCWith(pageIndex: 0, chapterIndex: currentChapterIndex + 1)
            ///         需要的页面并没有准备好，此时出现页面饥饿
            if nextPage == nil {
                self.postReaderStateNotification(state: .busy)
                pageHunger = true
            }
            return nextPage
        }
        if let back = viewController as? DUABackViewController {
            return self.getPageVCWith(pageIndex: back.index + 1, chapterIndex: back.chapterBelong)
        }
        return nil
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if let currentVC = pageViewController.viewControllers?.first, let previousVC = previousViewControllers.first {
            self.containerController(type: 0, currentController: currentVC, didFinishedTransition: completed, previousController: previousVC)
        }
    }
    
    func containerController(type: Int, currentController: UIViewController, didFinishedTransition finished: Bool, previousController: UIViewController) -> Void {
        prePageStartLocation = -1
        guard let curPage = currentController as? DUAPageViewController else { return }
        guard let previousPage = previousController as? DUAPageViewController else { return }
        print("当前页面所在章节 \(curPage.chapterBelong) 先前页面所在章节 \(previousPage.chapterBelong)")
        
        currentPageIndex = curPage.index
        
        var didStepIntoLastChapter = false
        var didStepIntoNextChapter = false
        if let pageVC = pageVC , type == 0 {
            didStepIntoLastChapter = (pageVC.willStepIntoLastChapter) && curPage.chapterBelong < previousPage.chapterBelong
            didStepIntoNextChapter = (pageVC.willStepIntoNextChapter) && curPage.chapterBelong > previousPage.chapterBelong
        } else if let translationVC = translationVC {
            didStepIntoLastChapter = (translationVC.willStepIntoLastChapter) && curPage.chapterBelong < previousPage.chapterBelong
            didStepIntoNextChapter = (translationVC.willStepIntoNextChapter) && curPage.chapterBelong > previousPage.chapterBelong
        }
        
        if didStepIntoNextChapter {
            print("进入下一章")
            updateChapterIndex(index: currentChapterIndex + 1)
            if type == 0 {
                pageVC?.willStepIntoLastChapter = true
                pageVC?.willStepIntoNextChapter = false
            }else {
                translationVC?.willStepIntoLastChapter = true
                translationVC?.willStepIntoNextChapter = false
            }

        }
        if didStepIntoLastChapter {
            print("进入上一章")
            updateChapterIndex(index: currentChapterIndex - 1)
            if type == 0 {
                pageVC?.willStepIntoNextChapter = true
                pageVC?.willStepIntoLastChapter = false
            }else {
                translationVC?.willStepIntoNextChapter = true
                translationVC?.willStepIntoLastChapter = false
            }
            
        }
        
        if currentPageIndex != 0 {
            if type == 0 {
                pageVC?.willStepIntoLastChapter = false
            }else {
                translationVC?.willStepIntoLastChapter = false
            }
            
        }
        if currentPageIndex != self.pageArrayFromCache(chapterIndex: currentChapterIndex).count - 1 {
            if type == 0 {
                pageVC?.willStepIntoNextChapter = false
            }else {
                translationVC?.willStepIntoNextChapter = false
            }
            
        }
        
        ///     进度信息必要时可以通过delegate回调出去
        print("当前阅读进度 章节 \(currentChapterIndex) 总页数 \(self.pageArrayFromCache(chapterIndex: currentChapterIndex).count) 当前页 \(currentPageIndex + 1)")
        if self.delegate?.reader(reader: readerProgressUpdated: curPage: totalPages: ) != nil {
            self.delegate?.reader(reader: self, readerProgressUpdated: currentChapterIndex, curPage: currentPageIndex + 1, totalPages: self.pageArrayFromCache(chapterIndex: currentChapterIndex).count)
        }

    }
    
    
    // MARK:--Table View Delegate
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return config.contentFrame.height
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.tableView?.dataArray.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell: DUATableViewCell = self.tableView?.dequeueReusableCell(withIdentifier: "dua.reader.cell") as? DUATableViewCell else { fatalError("cell 复用错误") }
//        if let subviews = cell.contentView.subviews {
//            for item in subviews {
//                item.removeFromSuperview()
//            }
//        }
//        cell = DUATableViewCell.init(style: UITableViewCellStyle.default, reuseIdentifier: "dua.reader.cell")
//
        if let pageModel = self.tableView?.dataArray[indexPath.row] {
            cell.configCellWith(pageModel: pageModel, config: config)
        }
        
        
        return cell
    }
    
    
//    func scrollViewDidScroll(_ scrollView: UIScrollView) {
//        if tableView?.isReloading ?? false {
//            return
//        }
//        if scrollView.contentOffset.y <= 0 {
//            scrollView.contentOffset.y = 0
//            // cell index = 0 需要请求上一章
//            if tableView?.arrivedZeroOffset == false {
//                self.requestLastChapterForTableView()
//            }
//            tableView?.arrivedZeroOffset = true
//        }else {
//            tableView?.arrivedZeroOffset = false
//        }
//        
//        let basePoint = CGPoint(x: config.contentFrame.width/2.0, y: scrollView.contentOffset.y + config.contentFrame.height/2.0)
//        let majorIndexPath = tableView?.indexPathForRow(at: basePoint)
//        
//        if majorIndexPath!.row > tableView!.cellIndex { // 向后翻页
//            
//            prePageStartLocation = -1
//            tableView?.cellIndex = majorIndexPath!.row
//            currentPageIndex = (self.tableView?.dataArray[tableView!.cellIndex].pageIndex)!
//            print("进入下一页 页码 \(currentPageIndex)")
//            
//            if currentPageIndex == 0 {
//                print("跳入下一章，从 \(currentChapterIndex) 到 \(currentChapterIndex + 1)")
//                updateChapterIndex(index: currentChapterIndex + 1)
//                self.statusBarForTableView?.totalPageCounts = self.pageArrayFromCache(chapterIndex: currentChapterIndex).count
//            }
//            self.statusBarForTableView?.curPageIndex = currentPageIndex
//            
//            // 到达本章节最后一页，请求下一章
//            if tableView?.cellIndex == (self.tableView?.dataArray.count)! - 1 {
//                self.requestNextChapterForTableView()
//            }
//            
//            if self.delegate?.reader(reader: readerProgressUpdated: curPage: totalPages: ) != nil {
//                self.delegate?.reader(reader: self, readerProgressUpdated: currentChapterIndex, curPage: currentPageIndex + 1, totalPages: self.pageArrayFromCache(chapterIndex: currentChapterIndex).count)
//            }
//        }else if majorIndexPath!.row < tableView!.cellIndex {     //向前翻页
//            prePageStartLocation = -1
//            tableView?.cellIndex = majorIndexPath!.row
//            currentPageIndex = (self.tableView?.dataArray[tableView!.cellIndex].pageIndex)!
//            print("进入上一页 页码 \(currentPageIndex)")
//            
//            let previousPageIndex = self.tableView!.dataArray[tableView!.cellIndex + 1].pageIndex
//            if currentChapterIndex - 1 > 0 && currentPageIndex == self.pageArrayFromCache(chapterIndex: currentChapterIndex - 1).count - 1 && previousPageIndex == 0 {
//                print("跳入上一章，从 \(currentChapterIndex) 到 \(currentChapterIndex - 1)")
//                updateChapterIndex(index: currentChapterIndex - 1)
//                self.statusBarForTableView?.totalPageCounts = self.pageArrayFromCache(chapterIndex: currentChapterIndex).count
//
//            }
//            self.statusBarForTableView?.curPageIndex = currentPageIndex
//            
//            if self.delegate?.reader(reader: readerProgressUpdated: curPage: totalPages: ) != nil {
//                self.delegate?.reader(reader: self, readerProgressUpdated: currentChapterIndex, curPage: currentPageIndex + 1, totalPages: self.pageArrayFromCache(chapterIndex: currentChapterIndex).count)
//            }
//        }
//    }
    
    // MARK: DUATranslationController Delegate
    
    func translationController(translationController: DUAtranslationController, controllerAfter controller: UIViewController?) -> UIViewController? {
        print("向后翻页~~~~~")
        let nextIndex: Int
        var nextPage: DUAPageViewController? = nil
        let pageArray = self.pageArrayFromCache(chapterIndex: currentChapterIndex)
        if let page = controller as? DUAPageViewController {
            nextIndex = page.index + 1
            if nextIndex == pageArray.count {
                if currentChapterIndex + 1 > totalChapterModels.count {
                    return nil
                }
                translationVC?.willStepIntoNextChapter = true
                self.requestChapterWith(index: currentChapterIndex + 1)
                nextPage = self.getPageVCWith(pageIndex: 0, chapterIndex: currentChapterIndex + 1)
                ///         需要的页面并没有准备好，此时出现页面饥饿
                if nextPage == nil {
                    self.postReaderStateNotification(state: .busy)
                    pageHunger = true
                    return nil
                }
            }else {
                nextPage = self.getPageVCWith(pageIndex: nextIndex, chapterIndex: page.chapterBelong)
            }
        }
        
        return nextPage
    }
    
    func translationController(translationController: DUAtranslationController, controllerBefore controller: UIViewController?) -> UIViewController? {
        
        print("向前翻页")
        var nextPage: DUAPageViewController? = nil
        if let page = controller as? DUAPageViewController {
            var nextIndex = page.index - 1
            if nextIndex < 0 {
                if currentChapterIndex <= 1 {
                    return nil
                }
                self.translationVC?.willStepIntoLastChapter = true
                self.requestChapterWith(index: currentChapterIndex - 1)
                nextIndex = self.pageArrayFromCache(chapterIndex: currentChapterIndex - 1).count - 1
                nextPage = self.getPageVCWith(pageIndex: nextIndex, chapterIndex: currentChapterIndex - 1)
                ///         需要的页面并没有准备好，此时出现页面饥饿
                if nextPage == nil {
                    self.postReaderStateNotification(state: .busy)
                    pageHunger = true
                    return nil
                }
            } else {
                nextPage = self.getPageVCWith(pageIndex: nextIndex, chapterIndex: page.chapterBelong)
            }
        }
        
        return nextPage
    }
    
    func translationController(translationController: DUAtranslationController, willTransitionTo controller: UIViewController?) {
        print("willTransitionTo")
    }
    
    func translationController(translationController: DUAtranslationController, didFinishAnimating finished: Bool, previousController: UIViewController?, transitionCompleted completed: Bool)
    {
        if let vc = translationController.childViewControllers.first,
           let previousController = previousController {
            self.containerController(type: 1, currentController: vc, didFinishedTransition: completed, previousController: previousController)
        }
    }

}

extension DUAReader: UICollectionViewDelegate, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return currentChapterDataSource.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ReaderContentCell", for: indexPath) as? ReaderContentCell else {
            fatalError("ReaderContentCell 复用错误")
        }
        cell.pageModel = currentChapterDataSource[indexPath.item]
        return cell
    }
    
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item == currentChapterDataSource.count - 2 {
            // 提前加载下一章节
            requestNextChapterForTableView()
        }
    }
    
}
