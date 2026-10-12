import Foundation
import UIKit
import Display

/// A bar that sits right above the tab bar on every tab, like the now-playing bar of Apple Music
/// (`UITabBarController.bottomAccessory`, which needs the system tab bar controller). The tab bar
/// owns its placement and visibility; the owner of the content only lays it out at the given size.
public final class TabBarBottomAccessory {
    public static let height: CGFloat = 48.0
    
    public let view: UIView
    public let update: (CGSize, ContainedViewLayoutTransition) -> Void
    
    public init(view: UIView, update: @escaping (CGSize, ContainedViewLayoutTransition) -> Void) {
        self.view = view
        self.update = update
    }
}
