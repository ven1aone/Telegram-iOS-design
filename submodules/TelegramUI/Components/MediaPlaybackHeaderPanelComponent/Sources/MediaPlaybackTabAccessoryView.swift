import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import TelegramUIPreferences
import ComponentFlow
import AccountContext
import TelegramCore
import GlobalControlPanelsContext
import SwiftSignalKit
import UniversalMediaPlayer
import PhotoResources
import GlassBackgroundComponent

/// The now-playing bar, modelled on Apple Music's tab bar accessory: artwork, title and artist,
/// play/pause and next. Shown above the tab bar (with its own glass) and at the top of chats inside
/// the header panel container (whose glass it uses, with a close button). Tapping it opens what is
/// playing (`openMediaPlaybackPlayer`), and the music player morphs out of the bar.
public final class MediaPlaybackTabAccessoryView: UIView {
    /// The artwork is a circle concentric with the bar: the same inset on the top, left and bottom.
    private static let artSize: CGFloat = 34.0
    
    private let context: AccountContext
    private let controller: () -> ViewController?
    private let shouldPerformAction: ((@escaping () -> Void) -> Void)?

    private let backgroundView: GlassBackgroundView?
    private let albumArtNode: TransformImageNode
    private let titleLabel: UILabel
    private let subtitleLabel: UILabel
    private let playPauseButton: UIButton
    private let nextButton: UIButton
    private let closeButton: UIButton?

    private var data: GlobalControlPanelsContext.MediaPlayback?
    private var theme: PresentationTheme?
    private var currentAlbumArtKey: (SharedMediaPlaybackAlbumArt?, EngineMedia.Id?)?
    private var isPlaying: Bool = false

    private var statusDisposable: Disposable?
    private let preloadDisposable = MetaDisposable()

    public init(context: AccountContext, controller: @escaping () -> ViewController?, hasBackground: Bool = true, showsCloseButton: Bool = false, shouldPerformAction: ((@escaping () -> Void) -> Void)? = nil) {
        self.context = context
        self.controller = controller
        self.shouldPerformAction = shouldPerformAction
        
        self.backgroundView = hasBackground ? GlassBackgroundView() : nil
        self.albumArtNode = TransformImageNode()
        self.albumArtNode.isUserInteractionEnabled = false
        self.albumArtNode.clipsToBounds = true
        self.albumArtNode.cornerRadius = MediaPlaybackTabAccessoryView.artSize * 0.5

        self.titleLabel = UILabel()
        self.titleLabel.font = Font.semibold(15.0)
        self.subtitleLabel = UILabel()
        self.subtitleLabel.font = Font.regular(13.0)

        self.playPauseButton = UIButton(type: .system)
        self.nextButton = UIButton(type: .system)
        self.closeButton = showsCloseButton ? UIButton(type: .system) : nil
        
        super.init(frame: CGRect())
        
        if let backgroundView = self.backgroundView {
            self.addSubview(backgroundView)
        }
        self.addSubview(self.albumArtNode.view)
        self.addSubview(self.titleLabel)
        self.addSubview(self.subtitleLabel)
        self.addSubview(self.playPauseButton)
        self.addSubview(self.nextButton)

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19.0, weight: .semibold)
        self.playPauseButton.setPreferredSymbolConfiguration(symbolConfiguration, forImageIn: .normal)
        self.nextButton.setPreferredSymbolConfiguration(symbolConfiguration, forImageIn: .normal)
        self.nextButton.setImage(UIImage(systemName: "forward.fill"), for: .normal)
        self.playPauseButton.addTarget(self, action: #selector(self.playPausePressed), for: .touchUpInside)
        self.nextButton.addTarget(self, action: #selector(self.nextPressed), for: .touchUpInside)
        if let closeButton = self.closeButton {
            self.addSubview(closeButton)
            closeButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold), forImageIn: .normal)
            closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        }
        self.updatePlayPauseIcon()

        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))

        self.statusDisposable = (context.sharedContext.mediaManager.globalMediaPlayerState
        |> map { value -> Bool in
            guard let value, case let .state(state) = value.1 else {
                return false
            }
            switch state.status.status {
            case .playing:
                return true
            case .paused:
                return false
            case let .buffering(_, whilePlaying, _, _):
                return whilePlaying
            }
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak self] isPlaying in
            guard let self else {
                return
            }
            self.isPlaying = isPlaying
            self.updatePlayPauseIcon()
        })
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.statusDisposable?.dispose()
        self.preloadDisposable.dispose()
    }

    private func updatePlayPauseIcon() {
        self.playPauseButton.setImage(UIImage(systemName: self.isPlaying ? "pause.fill" : "play.fill"), for: .normal)
    }

    private func performAction(_ action: @escaping () -> Void) {
        if let shouldPerformAction = self.shouldPerformAction {
            shouldPerformAction(action)
        } else {
            action()
        }
    }
    
    @objc private func playPausePressed() {
        guard let data = self.data else {
            return
        }
        self.performAction({ [weak self] in
            self?.context.sharedContext.mediaManager.playlistControl(.playback(.togglePlayPause), type: data.kind)
        })
    }
    
    @objc private func nextPressed() {
        guard let data = self.data else {
            return
        }
        // The playlist's `.previous` is the next track in display order (as in the old header panel).
        self.performAction({ [weak self] in
            self?.context.sharedContext.mediaManager.playlistControl(.previous, type: data.kind)
        })
    }
    
    @objc private func closePressed() {
        guard let data = self.data else {
            return
        }
        self.context.sharedContext.mediaManager.setPlaylist(nil, type: data.kind, control: SharedMediaPlayerControlAction.playback(.pause))
    }
    
    @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
        guard case .ended = recognizer.state, let data = self.data else {
            return
        }
        self.performAction({ [weak self] in
            guard let self, let controller = self.controller() else {
                return
            }
            openMediaPlaybackPlayer(context: self.context, data: data, controller: controller, sourceView: self, expandFromView: self, preloadDisposable: self.preloadDisposable)
        })
    }
    
    public func update(data: GlobalControlPanelsContext.MediaPlayback, theme: PresentationTheme, strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder) {
        self.data = data
        self.theme = theme

        var title = ""
        var subtitle = ""
        var albumArt: SharedMediaPlaybackAlbumArt?
        if let displayData = data.item.displayData {
            switch displayData {
            case let .music(titleValue, performer, albumArtValue, _, _):
                title = titleValue ?? strings.MediaPlayer_UnknownTrack
                subtitle = performer ?? strings.MediaPlayer_UnknownArtist
                albumArt = albumArtValue
            case let .voice(author, _):
                title = author?.displayTitle(strings: strings, displayOrder: nameDisplayOrder) ?? ""
                subtitle = strings.MusicPlayer_VoiceNote
            case let .instantVideo(author, _, _):
                title = author?.displayTitle(strings: strings, displayOrder: nameDisplayOrder) ?? ""
                subtitle = strings.Message_VideoMessage
            }
        }
        self.titleLabel.text = title
        self.titleLabel.textColor = theme.rootController.navigationBar.primaryTextColor
        self.subtitleLabel.text = subtitle
        self.subtitleLabel.textColor = theme.rootController.navigationBar.secondaryTextColor
        self.playPauseButton.tintColor = theme.rootController.navigationBar.primaryTextColor
        self.nextButton.tintColor = theme.rootController.navigationBar.primaryTextColor
        self.closeButton?.tintColor = theme.rootController.navigationBar.secondaryTextColor

        var fileReference: FileMediaReference?
        if let source = data.item.playbackData?.source, case let .telegramFile(reference, _, _) = source {
            fileReference = reference
        }
        let albumArtKey = (albumArt, fileReference?.media.fileId)
        if self.currentAlbumArtKey == nil || self.currentAlbumArtKey!.0 != albumArtKey.0 || self.currentAlbumArtKey!.1 != albumArtKey.1 {
            self.currentAlbumArtKey = albumArtKey
            self.albumArtNode.setSignal(playerAlbumArt(engine: self.context.engine, fileReference: fileReference, albumArt: albumArt, thumbnail: true))
        }

        self.setNeedsLayout()
    }

    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        let isDark = self.theme?.overallDarkAppearance ?? false
        if let backgroundView = self.backgroundView {
            transition.updateFrame(view: backgroundView, frame: CGRect(origin: CGPoint(), size: size))
            backgroundView.update(size: size, cornerRadius: size.height * 0.5, isDark: isDark, tintColor: .init(kind: .panel), isInteractive: true, transition: ComponentTransition(transition))
        }
        
        let artInset = floor((size.height - MediaPlaybackTabAccessoryView.artSize) * 0.5)
        let artSize = CGSize(width: MediaPlaybackTabAccessoryView.artSize, height: MediaPlaybackTabAccessoryView.artSize)
        let artFrame = CGRect(origin: CGPoint(x: artInset, y: artInset), size: artSize)
        let applyAlbumArt = self.albumArtNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(radius: artSize.width * 0.5), imageSize: artSize, boundingSize: artSize, intrinsicInsets: UIEdgeInsets()))
        applyAlbumArt()
        transition.updateFrame(node: self.albumArtNode, frame: artFrame)
        
        let buttonSize = CGSize(width: 40.0, height: size.height)
        var trailingX = size.width - artInset - 2.0
        if let closeButton = self.closeButton {
            let closeFrame = CGRect(origin: CGPoint(x: trailingX - 34.0, y: 0.0), size: CGSize(width: 34.0, height: size.height))
            transition.updateFrame(view: closeButton, frame: closeFrame)
            trailingX = closeFrame.minX
        }
        let nextFrame = CGRect(origin: CGPoint(x: trailingX - buttonSize.width, y: 0.0), size: buttonSize)
        let playPauseFrame = CGRect(origin: CGPoint(x: nextFrame.minX - buttonSize.width, y: 0.0), size: buttonSize)
        transition.updateFrame(view: self.nextButton, frame: nextFrame)
        transition.updateFrame(view: self.playPauseButton, frame: playPauseFrame)
        
        let textX = artFrame.maxX + 10.0
        let textWidth = max(0.0, playPauseFrame.minX - 4.0 - textX)
        transition.updateFrame(view: self.titleLabel, frame: CGRect(x: textX, y: floor(size.height * 0.5) - 19.0, width: textWidth, height: 20.0))
        transition.updateFrame(view: self.subtitleLabel, frame: CGRect(x: textX, y: floor(size.height * 0.5) + 1.0, width: textWidth, height: 17.0))
    }
}
