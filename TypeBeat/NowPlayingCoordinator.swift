import Foundation
import MediaPlayer
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Owns the lock-screen / Control-Center Now Playing widget. Observes
/// `AudioManager` and `AutoDJ` and rewrites the widget's metadata whenever
/// any of their state changes; wires Control-Center play/pause back into
/// the audio engine via `MPRemoteCommandCenter`.
///
/// AudioManager doesn't need to know about lock-screen UI — keeping this in
/// a separate coordinator means the audio engine stays focused on audio.
@MainActor
final class NowPlayingCoordinator {
    private let audioManager: AudioManager
    private let autoDJ: AutoDJ

    init(audioManager: AudioManager, autoDJ: AutoDJ) {
        self.audioManager = audioManager
        self.autoDJ = autoDJ
        setupRemoteCommands()
        startObserving()
        updateInfo()
    }

    // MARK: - Remote commands

    /// Wires Control-Center / lock-screen play, pause, and toggle commands
    /// through to the audio engine.
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak audioManager] _ in
            guard let audioManager else { return .commandFailed }
            Task { @MainActor in await audioManager.playWithDefaults() }
            return .success
        }
        center.pauseCommand.addTarget { [weak audioManager] _ in
            guard let audioManager else { return .commandFailed }
            Task { @MainActor in audioManager.stopAllPlayers() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak audioManager] _ in
            guard let audioManager else { return .commandFailed }
            Task { @MainActor in
                if audioManager.isPlaying {
                    audioManager.stopAllPlayers()
                } else {
                    await audioManager.playWithDefaults()
                }
            }
            return .success
        }
    }

    // MARK: - Observation

    /// `withObservationTracking` fires its `onChange` once when any of the
    /// read properties change, then needs re-arming. Each fire re-installs
    /// itself so the coordinator stays subscribed for the app's lifetime.
    private func startObserving() {
        withObservationTracking {
            _ = audioManager.isPlaying
            _ = audioManager.bpm
            _ = audioManager.activeSamples
            _ = autoDJ.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateInfo()
                self?.startObserving()
            }
        }
    }

    // MARK: - Info payload

    private func updateInfo() {
        var info: [String: Any] = [:]
        let samples = audioManager.activeSamples
        if samples.isEmpty {
            info[MPMediaItemPropertyTitle] = "ClubSound"
            info[MPMediaItemPropertyArtist] = autoDJ.isEnabled ? "Auto Mix" : "DJ"
        } else {
            let titles = samples.map(\.title)
            info[MPMediaItemPropertyTitle] = titles.first ?? "ClubSound"
            info[MPMediaItemPropertyArtist] = titles.count > 1
                ? titles.dropFirst().joined(separator: " · ")
                : (autoDJ.isEnabled ? "Auto Mix" : "DJ")
        }
        info[MPMediaItemPropertyAlbumTitle] = "\(Int(audioManager.bpm)) BPM"
        info[MPNowPlayingInfoPropertyPlaybackRate] = audioManager.isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioManager.loopProgress() * audioManager.masterLoopDuration
        info[MPMediaItemPropertyPlaybackDuration] = audioManager.masterLoopDuration
        info[MPNowPlayingInfoPropertyIsLiveStream] = false
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        #if canImport(UIKit)
        if let art = artworkImage() {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        #endif

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    #if canImport(UIKit)
    /// Lock-screen artwork. Uses the `artwork` image set in `Assets.xcassets`,
    /// which is a direct copy of the AppIcon source (`icon.png`, 1024×1024).
    /// iOS doesn't expose `AppIcon` to `UIImage(named:)` directly, so the
    /// asset catalog needs an explicit imageset that points at the same
    /// source bitmap — that way the lock-screen widget shows the identical
    /// image as the home-screen icon, at full resolution.
    private func artworkImage() -> UIImage? {
        UIImage(named: "artwork")
    }
    #endif
}
