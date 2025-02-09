import Foundation

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var bpm: Double {
        didSet {
            UserDefaults.standard.set(bpm, forKey: "lastBPM")
        }
    }
    
    @Published var isPlaying: Bool {
        didSet {
            UserDefaults.standard.set(isPlaying, forKey: "wasPlaying")
        }
    }
    
    @Published var pitchLock: Bool {
        didSet {
            UserDefaults.standard.set(pitchLock, forKey: "pitchLockEnabled")
        }
    }
    
    private init() {
        // Restore saved state or use defaults
        self.bpm = UserDefaults.standard.double(forKey: "lastBPM") != 0 
            ? UserDefaults.standard.double(forKey: "lastBPM") 
            : 84.0
        
        self.isPlaying = UserDefaults.standard.bool(forKey: "wasPlaying")
        self.pitchLock = UserDefaults.standard.bool(forKey: "pitchLockEnabled")
    }
    
    func saveState() {
        UserDefaults.standard.synchronize()
    }
} 