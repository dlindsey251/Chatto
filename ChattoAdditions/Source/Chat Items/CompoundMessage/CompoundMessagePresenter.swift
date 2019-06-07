//
// The MIT License (MIT)
//
// Copyright (c) 2015-present Badoo Trading Limited.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Chatto

@available(iOS 11, *)
open class CompoundMessagePresenter<ViewModelBuilderT, InteractionHandlerT>
    : BaseMessagePresenter<CompoundBubbleView, ViewModelBuilderT, InteractionHandlerT> where
    ViewModelBuilderT: ViewModelBuilderProtocol,
    ViewModelBuilderT.ModelT: Equatable,
    InteractionHandlerT: BaseMessageInteractionHandlerProtocol,
    InteractionHandlerT.ViewModelT == ViewModelBuilderT.ViewModelT {

    public typealias ModelT = ViewModelBuilderT.ModelT
    public typealias ViewModelT = ViewModelBuilderT.ViewModelT

    public let compoundCellStyle: CompoundBubbleViewStyleProtocol
    private let contentFactories: [AnyMessageContentFactory<ModelT>]
    private lazy var layoutProvider: CompoundBubbleLayoutProvider = self.makeLayoutProvider()
    private let cache: Cache<CompoundBubbleLayoutProvider.Configuration, CompoundBubbleLayoutProvider>
    private let accessibilityIdentifier: String?
    private let menuPresenter: ChatItemMenuPresenterProtocol?
    private var modules: [MessageContentModule]?

    public init(
        messageModel: ModelT,
        viewModelBuilder: ViewModelBuilderT,
        interactionHandler: InteractionHandlerT?,
        contentFactories: [AnyMessageContentFactory<ModelT>],
        sizingCell: CompoundMessageCollectionViewCell<ModelT>,
        baseCellStyle: BaseMessageCollectionViewCellStyleProtocol,
        compoundCellStyle: CompoundBubbleViewStyleProtocol,
        cache: Cache<CompoundBubbleLayoutProvider.Configuration, CompoundBubbleLayoutProvider>,
        accessibilityIdentifier: String?
    ) {
        self.compoundCellStyle = compoundCellStyle
        self.contentFactories = contentFactories.filter { $0.canCreateMessageModule(forModel: messageModel) }
        self.cache = cache
        self.accessibilityIdentifier = accessibilityIdentifier
        self.menuPresenter = self.contentFactories.lazy.compactMap { $0.createMenuPresenter(forModel: messageModel) }.first
        super.init(
            messageModel: messageModel,
            viewModelBuilder: viewModelBuilder,
            interactionHandler: interactionHandler,
            sizingCell: sizingCell,
            cellStyle: baseCellStyle
        )
    }

    open override var canCalculateHeightInBackground: Bool {
        return true
    }

    open override class func registerCells(_ collectionView: UICollectionView) {
        // Cell registration is happening lazily, right before the moment when a cell is dequeued.
    }

    open override func dequeueCell(collectionView: UICollectionView, indexPath: IndexPath) -> UICollectionViewCell {
        let cellReuseIdentifier = self.compoundCellReuseId
        collectionView.register(CompoundMessageCollectionViewCell<ModelT>.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        return collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath)
    }

    open override func heightForCell(maximumWidth width: CGFloat,
                                       decorationAttributes: ChatItemDecorationAttributesProtocol?) -> CGFloat {
        let layoutConstants = self.cellStyle.layoutConstants(viewModel: self.messageViewModel)
        let maxWidth = (width * layoutConstants.maxContainerWidthPercentageForBubbleView)
        return self.layoutProvider.layout(forMaxWidth: maxWidth).size.height
    }

    open override func configureCell(_ cell: BaseMessageCollectionViewCell<CompoundBubbleView>,
                                       decorationAttributes: ChatItemDecorationAttributes,
                                       animated: Bool,
                                       additionalConfiguration: (() -> Void)?) {
        guard let compoundCell = cell as? CompoundMessageCollectionViewCell<ModelT> else {
            assertionFailure("\(cell) is not CompoundMessageCollectionViewCell<\(ModelT.self)>")
            return
        }

        super.configureCell(compoundCell, decorationAttributes: decorationAttributes, animated: animated) { [weak self] in
            defer { additionalConfiguration?() }
            guard let sSelf = self else { return }
            guard compoundCell.lastAppliedConfiguration != sSelf.messageModel else { return }
            compoundCell.lastAppliedConfiguration = sSelf.messageModel
            let modules = sSelf.contentFactories.map { $0.createMessageModule(forModel: sSelf.messageModel) }
            sSelf.modules = modules
            let bubbleView = compoundCell.bubbleView!
            bubbleView.viewModel = sSelf.messageViewModel
            bubbleView.style = sSelf.compoundCellStyle
            bubbleView.decoratedContentViews = modules.map { .init(module: $0) }
            bubbleView.layoutProvider = sSelf.layoutProvider
            bubbleView.accessibilityIdentifier = sSelf.accessibilityIdentifier
        }
    }

    open override func cellWillBeShown() {
        super.cellWillBeShown()
        self.modules?.forEach { $0.willBeShown() }
    }

    open override func cellWasHidden() {
        super.cellWasHidden()
        self.modules?.forEach { $0.wasHidden() }
    }

    open override func onCellBubbleTapped() {
        super.onCellBubbleTapped()
        self.modules?.forEach { $0.wasTapped() }
    }

    private func makeLayoutProvider() -> CompoundBubbleLayoutProvider {
        let contentLayoutProviders = self.contentFactories.map { $0.createLayoutProvider(forModel: self.messageModel) }
        let viewModel = self.messageViewModel
        let tailWidth = self.compoundCellStyle.tailWidth(forViewModel: viewModel)
        let configuration = CompoundBubbleLayoutProvider.Configuration(
            layoutProviders: contentLayoutProviders,
            tailWidth: tailWidth,
            isIncoming: viewModel.isIncoming
        )
        guard let provider = self.cache[configuration] else {
            let provider = CompoundBubbleLayoutProvider(configuration: configuration)
            self.cache[configuration] = provider
            return provider
        }
        return provider
    }

    private lazy var compoundCellReuseId = "compound-message-[\(self.contentFactories.map { $0.identifier }.joined(separator: "-"))]"

    // MARK: - ChatItemMenuPresenterProtocol

    open override func canShowMenu() -> Bool {
        return self.menuPresenter?.shouldShowMenu() ?? false
    }

    open override func canPerformMenuControllerAction(_ action: Selector) -> Bool {
        return self.menuPresenter?.canPerformMenuControllerAction(action) ?? false
    }

    open override func performMenuControllerAction(_ action: Selector) {
        self.menuPresenter?.performMenuControllerAction(action)
    }
}

@available(iOS 11, *)
private extension CompoundBubbleView.DecoratedView {
    init(module: MessageContentModule) {
        self.init(view: module.view,
                  showBorder: module.showBorder)
    }
}
