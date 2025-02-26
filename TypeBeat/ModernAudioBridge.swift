import Foundation
import AVFoundation
import Combine
import SwiftUI

/// Bridge class that maintains the same interface as AudioManager but uses the modern audio components
class ModernAudioBridge: ObservableObject {
    static let shared = ModernAudioBridge()
    
    // Published properties to match AudioManager's interface
    @Published var activeSamples: Set<Int> = []
    @Published var bpm: Double = 84.0 {
        didSet {
            audioEngine.tempo = bpm
        }
    }
    @Published var pitchLock: Bool = false {
        didSet {
            audioEngine.pitchLock = pitchLock
        }
    }
    @Published var isPlaying: Bool = false
    @Published var isEngineReady: Bool = false
    
    // Modern components
    private let audioEngine: ModernAudioEngine
    private var players: [Int: SamplePlayerProtocol] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Samples reference
    private let samples: [Sample] = TypeBeat.samples
    
    private init() {
        // Initialize the modern audio engine with default settings
        audioEngine = ModernAudioEngine(sampleRate: 44100, initialTempo: 84.0)
        
        // Setup publishers to keep our published properties in sync with the engine
        setupPublishers()
        
        // Initialize the engine
        setupEngine()
    }
    
    private func setupPublishers() {
        // Subscribe to tempo changes from the engine
        audioEngine.tempoPublisher
            .sink { [weak self] tempo in
                self?.bpm = tempo
            }
            .store(in: &cancellables)
        
        // Subscribe to playback state changes
        audioEngine.playbackStatePublisher
            .sink { [weak self] isPlaying in
                self?.isPlaying = isPlaying
            }
            .store(in: &cancellables)
    }
    
    private func setupEngine() {
        // Any additional setup needed for the engine
        isEngineReady = true
    }
    
    // MARK: - Public API to match AudioManager
    
    /// Add a sample to play
    @MainActor
    func addSampleToPlay(_ sample: Sample) async {
        // Check if we already have this sample
        if players[sample.id] != nil {
            return
        }
        
        // Create a new player for this sample
        if let player = audioEngine.loadSample(sample) {
            players[sample.id] = player
            activeSamples.insert(sample.id)
            
            // If already playing, start this player too
            if isPlaying {
                audioEngine.startPlayback()
            }
        }
    }
    
    /// Remove a sample from play
    func removeSampleFromPlay(_ sampleId: Int) {
        guard players[sampleId] != nil else { return }
        
        // Stop and remove the player
        audioEngine.unloadSample(withId: sampleId)
        players.removeValue(forKey: sampleId)
        activeSamples.remove(sampleId)
    }
    
    /// Start playback of all samples
    func play() {
        audioEngine.startPlayback()
    }
    
    /// Stop all playback
    func stopAllPlayers() {
        audioEngine.stopPlayback()
    }
    
    /// Set volume for a specific sample
    func setVolume(for sampleId: Int, volume: Float) {
        audioEngine.setVolume(for: sampleId, volume: volume)
    }
    
    /// Get the current phase of a sample (0.0-1.0)
    func getSamplePhase(for sampleId: Int) -> Double {
        guard let player = players[sampleId] else { return 0.0 }
        return player.currentPhase()
    }
    
    /// Update the BPM
    func updateBPM(to newBPM: Double) {
        bpm = newBPM
    }
    
    /// Get a sample by ID
    func getSample(by id: Int) -> Sample? {
        return samples.first { $0.id == id }
    }
    
    /// Find samples by BPM
    func findSamplesByBPM(_ targetBPM: Double) -> [Sample] {
        return samples.filter { $0.bpm == targetBPM }
    }
} 