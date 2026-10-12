import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import AvatarNode

/// A horizontally scrolling row of chats with music, shown above the music player's playlist: the
/// chat being played first, then the chats music was recently played from, then other chats found to
/// have music. Each chip shows the chat's avatar and a truncated title; tapping one switches the
/// playlist to that chat.
final class OverlayAudioPlayerChatChipsView: UIScrollView {
    struct Item: Equatable {
        let peer: EnginePeer
        
        var peerId: EnginePeer.Id {
            return self.peer.id
        }
    }
    
    private final class ChipView: UIControl {
        let avatarNode: AvatarNode
        let titleLabel: UILabel
        var peerId: EnginePeer.Id?
        
        override init(frame: CGRect) {
            self.avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 9.0))
            self.avatarNode.isUserInteractionEnabled = false
            self.titleLabel = UILabel()
            self.titleLabel.font = Font.medium(14.0)
            self.titleLabel.lineBreakMode = .byTruncatingTail
            self.titleLabel.isUserInteractionEnabled = false
            
            super.init(frame: frame)
            
            self.layer.cornerCurve = .continuous
            self.addSubview(self.avatarNode.view)
            self.addSubview(self.titleLabel)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    private static let chipHeight: CGFloat = 32.0
    private static let avatarSize: CGFloat = 24.0
    private static let maxTitleWidth: CGFloat = 120.0
    
    private var chips: [EnginePeer.Id: ChipView] = [:]
    private var selectedPeerId: EnginePeer.Id?
    
    var selected: ((EnginePeer.Id) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.showsHorizontalScrollIndicator = false
        self.showsVerticalScrollIndicator = false
        self.alwaysBounceHorizontal = true
        self.scrollsToTop = false
        self.contentInsetAdjustmentBehavior = .never
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(context: AccountContext, items: [Item], selectedPeerId: EnginePeer.Id?, theme: PresentationTheme, strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder, size: CGSize, sideInset: CGFloat) {
        let previousSelectedPeerId = self.selectedPeerId
        self.selectedPeerId = selectedPeerId
        
        let chipHeight = OverlayAudioPlayerChatChipsView.chipHeight
        let avatarSize = OverlayAudioPlayerChatChipsView.avatarSize
        let avatarInset = floor((chipHeight - avatarSize) * 0.5)
        let spacing: CGFloat = 8.0
        var x = sideInset
        var validIds = Set<EnginePeer.Id>()
        for item in items {
            validIds.insert(item.peerId)
            let chip: ChipView
            if let current = self.chips[item.peerId] {
                chip = current
            } else {
                chip = ChipView()
                chip.peerId = item.peerId
                chip.addTarget(self, action: #selector(self.chipPressed(_:)), for: .touchUpInside)
                self.chips[item.peerId] = chip
                self.addSubview(chip)
                chip.avatarNode.setPeer(context: context, theme: theme, peer: item.peer, displayDimensions: CGSize(width: avatarSize, height: avatarSize))
            }
            let isSelected = item.peerId == selectedPeerId
            chip.titleLabel.text = item.peer.displayTitle(strings: strings, displayOrder: nameDisplayOrder)
            chip.titleLabel.textColor = isSelected ? theme.list.itemCheckColors.foregroundColor : theme.list.itemPrimaryTextColor
            chip.backgroundColor = isSelected ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.08)
            
            let titleWidth = min(OverlayAudioPlayerChatChipsView.maxTitleWidth, ceil(chip.titleLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: chipHeight)).width))
            let width = avatarInset + avatarSize + 6.0 + titleWidth + 12.0
            chip.frame = CGRect(x: x, y: floor((size.height - chipHeight) * 0.5), width: width, height: chipHeight)
            chip.layer.cornerRadius = chipHeight * 0.5
            chip.avatarNode.frame = CGRect(x: avatarInset, y: avatarInset, width: avatarSize, height: avatarSize)
            chip.titleLabel.frame = CGRect(x: avatarInset + avatarSize + 6.0, y: 0.0, width: titleWidth, height: chipHeight)
            x += width + spacing
        }
        for (peerId, chip) in self.chips where !validIds.contains(peerId) {
            chip.removeFromSuperview()
            self.chips.removeValue(forKey: peerId)
        }
        self.contentSize = CGSize(width: max(size.width, x - spacing + sideInset), height: size.height)
        
        if previousSelectedPeerId != selectedPeerId, let selectedPeerId, let chip = self.chips[selectedPeerId] {
            self.scrollRectToVisible(chip.frame.insetBy(dx: -sideInset, dy: 0.0), animated: previousSelectedPeerId != nil)
        }
    }
    
    @objc private func chipPressed(_ chip: ChipView) {
        guard let peerId = chip.peerId else {
            return
        }
        self.selected?(peerId)
    }
}
