import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import SyncCore
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import StickerResources
import ItemListStickerPackItem
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import ShimmerEffect

final class ChatMediaInputStickerPackItem: ListViewItem {
    let account: Account
    let inputNodeInteraction: ChatMediaInputNodeInteraction
    let collectionId: ItemCollectionId
    let collectionInfo: StickerPackCollectionInfo
    let stickerPackItem: StickerPackItem?
    let selectedItem: () -> Void
    let index: Int
    let theme: PresentationTheme
    
    var selectable: Bool {
        return true
    }
    
    init(account: Account, inputNodeInteraction: ChatMediaInputNodeInteraction, collectionId: ItemCollectionId, collectionInfo: StickerPackCollectionInfo, stickerPackItem: StickerPackItem?, index: Int, theme: PresentationTheme, selected: @escaping () -> Void) {
        self.account = account
        self.inputNodeInteraction = inputNodeInteraction
        self.collectionId = collectionId
        self.collectionInfo = collectionInfo
        self.stickerPackItem = stickerPackItem
        self.selectedItem = selected
        self.index = index
        self.theme = theme
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatMediaInputStickerPackItemNode()
            node.contentSize = boundingSize
            node.insets = ChatMediaInputNode.setupPanelIconInsets(item: self, previousItem: previousItem, nextItem: nextItem)
            node.inputNodeInteraction = self.inputNodeInteraction
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in
                        node.updateStickerPackItem(account: self.account, info: self.collectionInfo, item: self.stickerPackItem, collectionId: self.collectionId, theme: self.theme)
                        node.updateAppearanceTransition(transition: .immediate)
                    })
                })
            }
        }
    }
    
    public func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            completion(ListViewItemNodeLayout(contentSize: node().contentSize, insets: ChatMediaInputNode.setupPanelIconInsets(item: self, previousItem: previousItem, nextItem: nextItem)), { _ in
                (node() as? ChatMediaInputStickerPackItemNode)?.updateStickerPackItem(account: self.account, info: self.collectionInfo, item: self.stickerPackItem, collectionId: self.collectionId, theme: self.theme)
            })
        }
    }
    
    func selected(listView: ListView) {
        self.selectedItem()
    }
}

private let boundingSize = CGSize(width: 41.0, height: 41.0)
private let boundingImageSize = CGSize(width: 28.0, height: 28.0)
private let highlightSize = CGSize(width: 35.0, height: 35.0)
private let verticalOffset: CGFloat = 3.0

final class ChatMediaInputStickerPackItemNode: ListViewItemNode {
    private let imageNode: TransformImageNode
    private var animatedStickerNode: AnimatedStickerNode?
    private var placeholderNode: StickerShimmerEffectNode?
    private let highlightNode: ASImageNode
    
    var inputNodeInteraction: ChatMediaInputNodeInteraction?
    var currentCollectionId: ItemCollectionId?
    private var currentThumbnailItem: StickerPackThumbnailItem?
    private var theme: PresentationTheme?
    
    private let stickerFetchedDisposable = MetaDisposable()
    
    override var visibility: ListViewItemNodeVisibility {
        didSet {
            self.visibilityStatus = self.visibility != .none
        }
    }
    
    private var visibilityStatus: Bool = false {
        didSet {
            if self.visibilityStatus != oldValue {
                let loopAnimatedStickers = self.inputNodeInteraction?.stickerSettings?.loopAnimatedStickers ?? false
                self.animatedStickerNode?.visibility = self.visibilityStatus && loopAnimatedStickers
            }
        }
    }
    
    init() {
        self.highlightNode = ASImageNode()
        self.highlightNode.isLayerBacked = true
        self.highlightNode.isHidden = true
        
        self.imageNode = TransformImageNode()
        self.imageNode.isLayerBacked = !smartInvertColorsEnabled()
                
        self.placeholderNode = StickerShimmerEffectNode()
        self.placeholderNode?.transform = CATransform3DMakeRotation(CGFloat.pi / 2.0, 0.0, 0.0, 1.0)
        
        self.highlightNode.frame = CGRect(origin: CGPoint(x: floor((boundingSize.width - highlightSize.width) / 2.0) + verticalOffset - UIScreenPixel, y: floor((boundingSize.height - highlightSize.height) / 2.0) - UIScreenPixel), size: highlightSize)
        
        self.imageNode.transform = CATransform3DMakeRotation(CGFloat.pi / 2.0, 0.0, 0.0, 1.0)
        
        super.init(layerBacked: false, dynamicBounce: false)
        
        self.addSubnode(self.highlightNode)
        self.addSubnode(self.imageNode)
        if let placeholderNode = self.placeholderNode {
            self.addSubnode(placeholderNode)
        }
        
        var firstTime = true
        self.imageNode.imageUpdated = { [weak self] image in
            guard let strongSelf = self else {
                return
            }
            if image != nil {
                strongSelf.removePlaceholder(animated: !firstTime)
                if firstTime {
                    strongSelf.imageNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            }
            firstTime = false
        }
    }
    
    deinit {
        self.stickerFetchedDisposable.dispose()
    }
    
    private func removePlaceholder(animated: Bool) {
        if let placeholderNode = self.placeholderNode {
            self.placeholderNode = nil
            if !animated {
                placeholderNode.removeFromSupernode()
            } else {
                placeholderNode.alpha = 0.0
                placeholderNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, completion: { [weak placeholderNode] _ in
                    placeholderNode?.removeFromSupernode()
                })
            }
        }
    }
    
    func updateStickerPackItem(account: Account, info: StickerPackCollectionInfo, item: StickerPackItem?, collectionId: ItemCollectionId, theme: PresentationTheme) {
        self.currentCollectionId = collectionId
        
        if self.theme !== theme {
            self.theme = theme
            
            self.highlightNode.image = PresentationResourcesChat.chatMediaInputPanelHighlightedIconImage(theme)
        }
        
        var thumbnailItem: StickerPackThumbnailItem?
        var resourceReference: MediaResourceReference?
        if let thumbnail = info.thumbnail {
            if info.flags.contains(.isAnimated) {
                thumbnailItem = .animated(thumbnail.resource)
                resourceReference = MediaResourceReference.stickerPackThumbnail(stickerPack: .id(id: info.id.id, accessHash: info.accessHash), resource: thumbnail.resource)
            } else {
                thumbnailItem = .still(thumbnail)
                resourceReference = MediaResourceReference.stickerPackThumbnail(stickerPack: .id(id: info.id.id, accessHash: info.accessHash), resource: thumbnail.resource)
            }
        } else if let item = item {
            if item.file.isAnimatedSticker {
                thumbnailItem = .animated(item.file.resource)
                resourceReference = MediaResourceReference.media(media: .standalone(media: item.file), resource: item.file.resource)
            } else if let dimensions = item.file.dimensions, let resource = chatMessageStickerResource(file: item.file, small: true) as? TelegramMediaResource {
                thumbnailItem = .still(TelegramMediaImageRepresentation(dimensions: dimensions, resource: resource, progressiveSizes: []))
                resourceReference = MediaResourceReference.media(media: .standalone(media: item.file), resource: resource)
            }
        }
        
        if self.currentThumbnailItem != thumbnailItem {
            self.currentThumbnailItem = thumbnailItem
            if let thumbnailItem = thumbnailItem {
                switch thumbnailItem {
                    case let .still(representation):
                        let imageSize = representation.dimensions.cgSize.aspectFitted(boundingImageSize)
                        let imageApply = self.imageNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(), imageSize: imageSize, boundingSize: imageSize, intrinsicInsets: UIEdgeInsets()))
                        imageApply()
                        self.imageNode.setSignal(chatMessageStickerPackThumbnail(postbox: account.postbox, resource: representation.resource, nilIfEmpty: true))
                        self.imageNode.frame = CGRect(origin: CGPoint(x: floor((boundingSize.width - imageSize.width) / 2.0) + verticalOffset, y: floor((boundingSize.height - imageSize.height) / 2.0)), size: imageSize)
                    case let .animated(resource):
                        let imageSize = boundingImageSize
                        let imageApply = self.imageNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(), imageSize: imageSize, boundingSize: imageSize, intrinsicInsets: UIEdgeInsets()))
                        imageApply()
                        self.imageNode.setSignal(chatMessageStickerPackThumbnail(postbox: account.postbox, resource: resource, animated: true, nilIfEmpty: true))
                        self.imageNode.frame = CGRect(origin: CGPoint(x: floor((boundingSize.width - imageSize.width) / 2.0) + verticalOffset, y: floor((boundingSize.height - imageSize.height) / 2.0)), size: imageSize)
                        
                        let loopAnimatedStickers = self.inputNodeInteraction?.stickerSettings?.loopAnimatedStickers ?? false
                        self.imageNode.isHidden = loopAnimatedStickers
                        
                        let animatedStickerNode: AnimatedStickerNode
                        if let current = self.animatedStickerNode {
                            animatedStickerNode = current
                        } else {
                            animatedStickerNode = AnimatedStickerNode()
                            self.animatedStickerNode = animatedStickerNode
                            animatedStickerNode.transform = CATransform3DMakeRotation(CGFloat.pi / 2.0, 0.0, 0.0, 1.0)
                            if let placeholderNode = self.placeholderNode {
                                self.insertSubnode(animatedStickerNode, belowSubnode: placeholderNode)
                            } else {
                                self.addSubnode(animatedStickerNode)
                            }
                            animatedStickerNode.setup(source: AnimatedStickerResourceSource(account: account, resource: resource), width: 80, height: 80, mode: .cached)
                        }
                        animatedStickerNode.visibility = self.visibilityStatus && loopAnimatedStickers
                        if let animatedStickerNode = self.animatedStickerNode {
                            animatedStickerNode.frame = CGRect(origin: CGPoint(x: floor((boundingSize.width - imageSize.width) / 2.0) + verticalOffset, y: floor((boundingSize.height - imageSize.height) / 2.0)), size: imageSize)
                        }
                }
                if let resourceReference = resourceReference {
                    self.stickerFetchedDisposable.set(fetchedMediaResource(mediaBox: account.postbox.mediaBox, reference: resourceReference).start())
                }
            }
                        
            if let placeholderNode = self.placeholderNode {
                let imageSize = boundingImageSize
                let placeholderFrame = CGRect(origin: CGPoint(x: floor((boundingSize.width - imageSize.width) / 2.0) + verticalOffset, y: floor((boundingSize.height - imageSize.height) / 2.0)), size: imageSize)
                placeholderNode.frame = placeholderFrame
                
                placeholderNode.update(backgroundColor: nil, foregroundColor: theme.chat.inputMediaPanel.stickersSectionTextColor.blitOver(theme.chat.inputPanel.panelBackgroundColor, alpha: 0.4), shimmeringColor: theme.chat.inputMediaPanel.panelHighlightedIconBackgroundColor.withMultipliedAlpha(0.2), data: info.immediateThumbnailData, size: imageSize, imageSize: CGSize(width: 100.0, height: 100.0))
            }
            
            self.updateIsHighlighted()
        }
    }
    
    override func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
        if let placeholderNode = self.placeholderNode {
            placeholderNode.updateAbsoluteRect(rect, within: containerSize)
        }
    }
    
    func updateIsHighlighted() {
        assert(Queue.mainQueue().isCurrent())
        if let currentCollectionId = self.currentCollectionId, let inputNodeInteraction = self.inputNodeInteraction {
            self.highlightNode.isHidden = inputNodeInteraction.highlightedItemCollectionId != currentCollectionId
        }
    }
    
    func updateAppearanceTransition(transition: ContainedViewLayoutTransition) {
        assert(Queue.mainQueue().isCurrent())
        if let inputNodeInteraction = self.inputNodeInteraction {
            transition.updateSublayerTransformScale(node: self, scale: inputNodeInteraction.appearanceTransition)
        }
    }
    
    override func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}
