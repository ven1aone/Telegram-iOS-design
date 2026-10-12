import Foundation
import UIKit

public protocol OverlayAudioPlayerController: AnyObject {
    /// A view the player expands out of when it opens and collapses back into when it closes (the
    /// now-playing bar above the tab bar). The view is hidden while the player covers it.
    var expandsFromView: UIView? { get set }
    /// The bar's frame in window coordinates and a picture of it, both taken when it was tapped (see
    /// `prepareMediaPlayerExpansion`).
    var expandsFromFrame: CGRect? { get set }
    var expandsFromSnapshot: UIView? { get set }
}
