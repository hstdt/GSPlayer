//
//  VideoPlayerView.swift
//  GSPlayer
//
//  Created by Gesen on 2019/4/20.
//  Copyright © 2019 Gesen. All rights reserved.
//

import UIKit
import AVFoundation

public class VideoPlayerView: UIView {
    
    public enum State {
        
        /// None
        case none
        
        /// From the first load to get the first frame of the video
        case loading
        
        /// Playing now
        case playing
        
        /// Pause, will be called repeatedly when the buffer progress changes
        case paused(playing: Double, buffering: Double)
        
        /// An error occurred and cannot continue playing
        case error(NSError)
    }
    
    public enum PausedReason {
        
        /// Pause because the player is not visible, stateDidChanged is not called when the buffer progress changes
        case hidden
        
        /// Pause triggered by user interaction, default behavior
        case userInteraction
        
        /// Waiting for resource completion buffering
        case waitingKeepUp
    }
    
    /// An object that manages a player's visual output.
    public let playerLayer = AVPlayerLayer()
    
    /// Playback status changes, such as from play to pause.
    public var stateDidChanged: ((State) -> Void)?
    
    /// Replay after playing to the end.
    public var replay: (() -> Void)?
    
    /// Get current video status.
    public private(set) var state: State = .none {
        didSet { stateDidChanged(state: state, previous: oldValue) }
    }
    
    /// The reason the video was paused.
    public private(set) var pausedReason: PausedReason = .waitingKeepUp
    
    /// Number of replays.
    public private(set) var replayCount: Int = 0
    
    /// Played progress, value range 0-1.
    public var playing: Double {
        return isLoaded ? player?.playing ?? 0 : 0
    }
    
    /// Played length in seconds.
    public var currentDuration: Double {
        return isLoaded ? player?.currentDuration ?? 0 : 0
    }
    
    /// Buffered progress, value range 0-1.
    public var buffering: Double {
        return isLoaded ? player?.buffering ?? 0 : 0
    }
    
    /// Buffered length in seconds.
    public var currentBufferDuration: Double {
        return isLoaded ? player?.currentBufferDuration ?? 0 : 0
    }
    
    /// Total video duration in seconds.
    public var totalDuration: Double {
        return isLoaded ? player?.totalDuration ?? 0 : 0
    }
    
    /// The total watch time of this video, in seconds.
    public var watchDuration: Double {
        return isLoaded ? currentDuration + totalDuration * Double(replayCount) : 0
    }
    
    /// Whether the video is muted, only for this instance.
    public var isMuted: Bool {
        get { return player?.isMuted ?? false }
        set { player?.isMuted = newValue }
    }
    
    /// Video volume, only for this instance.
    public var volume: Double {
        get { return player?.volume.double ?? 0 }
        set { player?.volume = newValue.float }
    }
    
    private var isLoaded = false
    private var isReplay = false
    
    private var playerBufferingObservation: NSKeyValueObservation?
    private var playerItemKeepUpObservation: NSKeyValueObservation?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerLayerReadyForDisplayObservation: NSKeyValueObservation?
    private var playerTimeControlStatusObservation: NSKeyValueObservation?
    
    // MARK: - Lifecycle
    
    public override var contentMode: UIView.ContentMode {
        didSet {
            switch contentMode {
            case .scaleAspectFill:  playerLayer.videoGravity = .resizeAspectFill
            case .scaleAspectFit:   playerLayer.videoGravity = .resizeAspect
            default:                playerLayer.videoGravity = .resize
            }
        }
    }
    
    public init() {
        super.init(frame: .zero)
        configureInit()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configureInit()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        guard playerLayer.superlayer == layer else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
    
}

public extension VideoPlayerView {
    
    /// Play a video of the specified url.
    ///
    /// - Parameter url: Can be a local or remote URL
    func play(for url: URL) {
        
        observe(player: nil)
        observe(playerItem: nil)
        
        self.player?.currentItem?.cancelPendingSeeks()
        self.player?.currentItem?.asset.cancelLoading()
        
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        
        let playerItem = AVPlayerItem(loader: url)
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        
        self.player = player
        self.pausedReason = .waitingKeepUp
        self.replayCount = 0
        self.isLoaded = false
        
        if playerItem.isEnoughToPlay || url.isFileURL {
            state = .none
            isLoaded = true
            player.play()
        } else {
            state = .loading
        }
        
        player.replaceCurrentItem(with: playerItem)
        
        observe(player: player)
        observe(playerItem: playerItem)
    }
    
    /// Pause video.
    ///
    /// - Parameter reason: Reason for pause
    func pause(reason: PausedReason) {
        pausedReason = reason
        player?.pause()
    }
    
    /// Continue playing video.
    func resume() {
        pausedReason = .waitingKeepUp
        player?.play()
    }
    
}

private extension VideoPlayerView {
    
    var player: AVPlayer? {
        get { return playerLayer.player }
        set { playerLayer.player = newValue }
    }
    
}

private extension VideoPlayerView {
    
    func configureInit() {
        
        isHidden = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(notification:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        
        layer.addSublayer(playerLayer)
    }
    
    func stateDidChanged(state: State, previous: State) {
        
        guard state != previous else {
            return
        }
        
        switch state {
        case .playing, .paused: isHidden = false
        default:                isHidden = true
        }
        
        stateDidChanged?(state)
    }
    
    func observe(player: AVPlayer?) {
        
        guard let player = player else {
            playerLayerReadyForDisplayObservation = nil
            playerTimeControlStatusObservation = nil
            return
        }
        
        playerLayerReadyForDisplayObservation = playerLayer.observe(\.isReadyForDisplay) { [unowned self, unowned player] playerLayer, _ in
            if playerLayer.isReadyForDisplay, player.rate > 0 {
                self.isLoaded = true
                self.state = .playing
            }
        }
        
        playerTimeControlStatusObservation = player.observe(\.timeControlStatus) { [unowned self] player, _ in
            switch player.timeControlStatus {
            case .paused:
                guard !self.isReplay else { break }
                self.state = .paused(playing: self.playing, buffering: self.buffering)
                if self.pausedReason == .waitingKeepUp { player.play() }
            case .waitingToPlayAtSpecifiedRate:
                break
            case .playing:
                if self.playerLayer.isReadyForDisplay, player.rate > 0 {
                    self.isLoaded = true
                    if self.playing == 0, self.isReplay { self.isReplay = false; break }
                    self.state = .playing
                }
            @unknown default:
                break
            }
        }
    }
    
    func observe(playerItem: AVPlayerItem?) {
        
        guard let playerItem = playerItem else {
            playerBufferingObservation = nil
            playerItemStatusObservation = nil
            playerItemKeepUpObservation = nil
            return
        }
        
        playerBufferingObservation = playerItem.observe(\.loadedTimeRanges) { [unowned self] item, _ in
            if case .paused = self.state, self.pausedReason != .hidden {
                self.state = .paused(playing: self.playing, buffering: self.buffering)
            }
            
            if self.buffering >= 0.99 || (self.currentBufferDuration - self.currentDuration) > 3 {
                VideoPreloadManager.shared.start()
            } else {
                VideoPreloadManager.shared.pause()
            }
        }
        
        playerItemStatusObservation = playerItem.observe(\.status) { [unowned self] item, _ in
            if item.status == .failed, let error = item.error as NSError? {
                self.state = .error(error)
            }
        }
        
        playerItemKeepUpObservation = playerItem.observe(\.isPlaybackLikelyToKeepUp) { [unowned self] item, _ in
            if item.isPlaybackLikelyToKeepUp {
                if self.player?.rate == 0, self.pausedReason == .waitingKeepUp {
                    self.player?.play()
                }
            }
        }
    }
    
    @objc func playerItemDidReachEnd(notification: Notification) {
        
        guard
            pausedReason == .waitingKeepUp,
            (notification.object as? AVPlayerItem) == player?.currentItem else {
            return
        }
        
        isReplay = true
        
        replay?()
        replayCount += 1
        
        player?.seek(to: CMTime.zero)
        player?.play()
    }
    
}

extension VideoPlayerView.State: Equatable {
    
    public static func == (lhs: VideoPlayerView.State, rhs: VideoPlayerView.State) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.loading, .loading):
            return true
        case (.playing, .playing):
            return true
        case let (.paused(p1, b1), .paused(p2, b2)):
            return (p1 == p2) && (b1 == b2)
        case let (.error(e1), .error(e2)):
            return e1 == e2
        default:
            return false
        }
    }
    
}