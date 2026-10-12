import Foundation
import UIKit
import Display
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import AccountContext
import TelegramCore
import GlobalControlPanelsContext
import SwiftSignalKit
import OverlayStatusController
import PresentationDataUtils

public final class MediaPlaybackHeaderPanelComponent: Component {
    public let context: AccountContext
    public let theme: PresentationTheme
    public let strings: PresentationStrings
    public let data: GlobalControlPanelsContext.MediaPlayback
    public let controller: () -> ViewController?
    public let shouldPerformAction: ((@escaping () -> Void) -> Void)?
    
    public init(
        context: AccountContext,
        theme: PresentationTheme,
        strings: PresentationStrings,
        data: GlobalControlPanelsContext.MediaPlayback,
        controller: @escaping () -> ViewController?,
        shouldPerformAction: ((@escaping () -> Void) -> Void)? = nil
    ) {
        self.context = context
        self.theme = theme
        self.strings = strings
        self.data = data
        self.controller = controller
        self.shouldPerformAction = shouldPerformAction
    }
    
    public static func ==(lhs: MediaPlaybackHeaderPanelComponent, rhs: MediaPlaybackHeaderPanelComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings !== rhs.strings {
            return false
        }
        if lhs.data != rhs.data {
            return false
        }
        return true
    }
    
    /// The now-playing panel at the top of chats and lists: the same bar as the tab bar accessory,
    /// drawn on the header panel container's glass, with a close button.
    public final class View: UIView {
        private var accessoryView: MediaPlaybackTabAccessoryView?
        private var component: MediaPlaybackHeaderPanelComponent?
        
        public override init(frame: CGRect) {
            super.init(frame: frame)
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(component: MediaPlaybackHeaderPanelComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            
            let accessoryView: MediaPlaybackTabAccessoryView
            if let current = self.accessoryView {
                accessoryView = current
            } else {
                accessoryView = MediaPlaybackTabAccessoryView(
                    context: component.context,
                    controller: { [weak self] in
                        return self?.component?.controller()
                    },
                    hasBackground: false,
                    showsCloseButton: true,
                    shouldPerformAction: { [weak self] action in
                        if let shouldPerformAction = self?.component?.shouldPerformAction {
                            shouldPerformAction(action)
                        } else {
                            action()
                        }
                    }
                )
                self.accessoryView = accessoryView
                self.addSubview(accessoryView)
            }
            
            let nameDisplayOrder = component.context.sharedContext.currentPresentationData.with({ $0 }).nameDisplayOrder
            accessoryView.update(data: component.data, theme: component.theme, strings: component.strings, nameDisplayOrder: nameDisplayOrder)
            
            let size = CGSize(width: availableSize.width, height: 48.0)
            transition.setFrame(view: accessoryView, frame: CGRect(origin: CGPoint(), size: size))
            accessoryView.updateLayout(size: size, transition: transition.containedViewLayoutTransition)
            
            return size
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

/// Opens what the now-playing item belongs to: the overlay music player for music, the message for
/// voice and video messages. Shared by the header panel and the tab bar accessory.
/// `expandFromView` is the view the music player grows out of (the tab bar's now-playing bar).
public func openMediaPlaybackPlayer(context: AccountContext, data: GlobalControlPanelsContext.MediaPlayback, controller: ViewController, sourceView: UIView?, expandFromView: UIView? = nil, preloadDisposable: MetaDisposable) {
    guard let navigationController = controller.navigationController as? NavigationController else {
        return
    }

    // A RICH message's audio plays out of an `InstantPageMediaPlaylist` — the file lives in
    // the message's `RichTextMessageAttribute`, not in `message.media` — so neither the item
    // id nor the location is a `PeerMessages*` one and the branch below never matched: the
    // mini player was inert for it. Open the same overlay music player the chat-history
    // playlists open, anchored on the message the playlist came from. That works because a
    // rich message IS `.music`-tagged (`tagsForStoreMessage` folds the attribute's media in),
    // so the player's own music-tagged history list finds it.
    if let instantPageLocation = data.playlistLocation as? InstantPagePlaylistLocation {
        // An Instant View page has no message to open — leave it inert, as before.
        guard let messageId = instantPageLocation.messageId else {
            return
        }
        guard case .music = data.kind else {
            // Voice / instant video: jump to the message, mirroring the non-music arm below.
            context.sharedContext.navigateToChat(accountId: context.account.id, peerId: messageId.peerId, messageId: messageId)
            return
        }
        let controllerContext: AccountContext
        if data.account.id == context.account.id {
            controllerContext = context
        } else {
            controllerContext = context.sharedContext.makeTempAccountContext(account: data.account)
        }
        // The queue is built from synthesized Local-id rows, one per track, so it
        // must be anchored on the PLAYING track's synthesized id — the rich
        // message's own id is not among those rows.
        var anchorMessageId = messageId
        if let indexProviding = data.item.id as? InstantPagePlaylistItemIndexProviding {
            anchorMessageId = EngineMessage.Id(peerId: messageId.peerId, namespace: Namespaces.Message.Local, id: Int32(clamping: indexProviding.instantPageMediaIndex))
        }
        let playerController = context.sharedContext.makeOverlayAudioPlayerController(context: controllerContext, chatLocation: .peer(id: messageId.peerId), type: data.kind, initialMessageId: anchorMessageId, initialOrder: data.playbackOrder, playlistLocation: instantPageLocation, parentNavigationController: navigationController)
        sourceView?.window?.endEditing(true)
        prepareMediaPlayerExpansion(playerController, from: expandFromView)
        playerController.navigationPresentation = .flatModal
        controller.push(playerController)
        return
    }

    if let id = data.item.id as? PeerMessagesMediaPlaylistItemId, let playlistLocation = data.playlistLocation as? PeerMessagesPlaylistLocation {
        if case .music = data.kind {
            switch playlistLocation {
            case .custom, .savedMusic:
                let controllerContext: AccountContext
                if data.account.id == context.account.id {
                    controllerContext = context
                } else {
                    controllerContext = context.sharedContext.makeTempAccountContext(account: data.account)
                }
                let playerController = context.sharedContext.makeOverlayAudioPlayerController(context: controllerContext, chatLocation: .peer(id: id.messageId.peerId), type: data.kind, initialMessageId: id.messageId, initialOrder: data.playbackOrder, playlistLocation: playlistLocation, parentNavigationController: navigationController)
                sourceView?.window?.endEditing(true)
                prepareMediaPlayerExpansion(playerController, from: expandFromView)
                playerController.navigationPresentation = .flatModal
                controller.push(playerController)
            case let .messages(chatLocation, _, _):
                let signal = context.sharedContext.messageFromPreloadedChatHistoryViewForLocation(id: id.messageId, location: ChatHistoryLocationInput(content: .InitialSearch(subject: MessageHistoryInitialSearchSubject(location: .id(id.messageId)), count: 60, highlight: true, setupReply: false), id: 0), context: context, chatLocation: chatLocation, subject: nil, chatLocationContextHolder: Atomic<ChatLocationContextHolder?>(value: nil), tag: .tag(EngineMessage.Tags.music))

                var cancelImpl: (() -> Void)?
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let progressSignal = Signal<Never, NoError> { [weak controller] subscriber in
                    let statusController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: {
                        cancelImpl?()
                    }))
                    controller?.present(statusController, in: .window(.root))
                    return ActionDisposable { [weak statusController] in
                        Queue.mainQueue().async() {
                            statusController?.dismiss()
                        }
                    }
                }
                |> runOn(Queue.mainQueue())
                |> delay(0.15, queue: Queue.mainQueue())
                let progressDisposable = MetaDisposable()
                var progressStarted = false
                preloadDisposable.set((signal
                |> afterDisposed {
                    Queue.mainQueue().async {
                        progressDisposable.dispose()
                    }
                }
                |> deliverOnMainQueue).start(next: { index in
                    if let _ = index.0 {
                        let controllerContext: AccountContext
                        if data.account.id == context.account.id {
                            controllerContext = context
                        } else {
                            controllerContext = context.sharedContext.makeTempAccountContext(account: data.account)
                        }
                        let playerController = context.sharedContext.makeOverlayAudioPlayerController(context: controllerContext, chatLocation: chatLocation, type: data.kind, initialMessageId: id.messageId, initialOrder: data.playbackOrder, playlistLocation: nil, parentNavigationController: navigationController)
                        sourceView?.window?.endEditing(true)
                        prepareMediaPlayerExpansion(playerController, from: expandFromView)
                        playerController.navigationPresentation = .flatModal
                        controller.push(playerController)
                    } else if index.1 {
                        if !progressStarted {
                            progressStarted = true
                            progressDisposable.set(progressSignal.start())
                        }
                    }
                }, completed: {
                }))
                cancelImpl = {
                    preloadDisposable.set(nil)
                }
            default:
                break
            }
        } else {
            context.sharedContext.navigateToChat(accountId: context.account.id, peerId: id.messageId.peerId, messageId: id.messageId)
        }
    }
}

/// Records where the player expands from while the bar is on screen: its frame in window coordinates
/// and a snapshot. The player appears a moment later, when the bar's tab may no longer be in the window.
func prepareMediaPlayerExpansion(_ playerController: ViewController & OverlayAudioPlayerController, from view: UIView?) {
    guard let view, view.window != nil, !view.bounds.isEmpty else {
        return
    }
    playerController.expandsFromView = view
    playerController.expandsFromFrame = view.convert(view.bounds, to: nil)
    playerController.expandsFromSnapshot = view.snapshotView(afterScreenUpdates: false)
}
