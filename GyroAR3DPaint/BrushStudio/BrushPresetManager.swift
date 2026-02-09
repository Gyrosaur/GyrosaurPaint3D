import SwiftUI
import Combine

@MainActor
class BrushPresetManager: ObservableObject {
    @Published var presets: [BrushDefinition] = []
    @Published var currentPreset: BrushDefinition
    @Published var userPresets: [BrushDefinition] = []
    
    private let userPresetsKey = "UserBrushPresets"
    private let currentPresetKey = "CurrentBrushPreset"
    
    init() {
        // Load defaults
        self.currentPreset = BrushDefinition.defaultSmooth
        self.presets = BrushDefinition.allDefaults
        
        // Load user presets
        loadUserPresets()
        loadCurrentPreset()
    }
    
    // MARK: - Preset Management
    
    func selectPreset(_ preset: BrushDefinition) {
        currentPreset = preset
        saveCurrentPreset()
    }
    
    func saveAsNewPreset(name: String) {
        var newPreset = currentPreset
        newPreset.id = UUID()
        newPreset.name = name
        newPreset.category = .custom
        
        userPresets.append(newPreset)
        saveUserPresets()
    }
    
    func updatePreset(_ preset: BrushDefinition) {
        if let index = userPresets.firstIndex(where: { $0.id == preset.id }) {
            userPresets[index] = preset
            saveUserPresets()
        }
        if currentPreset.id == preset.id {
            currentPreset = preset
            saveCurrentPreset()
        }
    }
    
    func deletePreset(_ preset: BrushDefinition) {
        userPresets.removeAll { $0.id == preset.id }
        saveUserPresets()
    }
    
    func duplicatePreset(_ preset: BrushDefinition) -> BrushDefinition {
        var duplicate = preset
        duplicate.id = UUID()
        duplicate.name = "\(preset.name) Copy"
        duplicate.category = .custom
        
        userPresets.append(duplicate)
        saveUserPresets()
        return duplicate
    }
    
    // MARK: - All Presets
    
    var allPresets: [BrushDefinition] {
        presets + userPresets
    }
    
    func presets(for category: BrushCategory) -> [BrushDefinition] {
        allPresets.filter { $0.category == category }
    }
    
    // MARK: - Persistence
    
    private func saveUserPresets() {
        do {
            let data = try JSONEncoder().encode(userPresets)
            UserDefaults.standard.set(data, forKey: userPresetsKey)
        } catch {
            print("Failed to save user presets: \(error)")
        }
    }
    
    private func loadUserPresets() {
        guard let data = UserDefaults.standard.data(forKey: userPresetsKey) else { return }
        do {
            userPresets = try JSONDecoder().decode([BrushDefinition].self, from: data)
        } catch {
            print("Failed to load user presets: \(error)")
        }
    }
    
    private func saveCurrentPreset() {
        do {
            let data = try JSONEncoder().encode(currentPreset)
            UserDefaults.standard.set(data, forKey: currentPresetKey)
        } catch {
            print("Failed to save current preset: \(error)")
        }
    }
    
    private func loadCurrentPreset() {
        guard let data = UserDefaults.standard.data(forKey: currentPresetKey) else { return }
        do {
            currentPreset = try JSONDecoder().decode(BrushDefinition.self, from: data)
        } catch {
            print("Failed to load current preset: \(error)")
        }
    }
    
    // MARK: - Export/Import
    
    func exportPreset(_ preset: BrushDefinition) -> Data? {
        try? JSONEncoder().encode(preset)
    }
    
    func importPreset(from data: Data) -> BrushDefinition? {
        guard let preset = try? JSONDecoder().decode(BrushDefinition.self, from: data) else { return nil }
        var imported = preset
        imported.id = UUID() // New ID to avoid conflicts
        imported.category = .custom
        userPresets.append(imported)
        saveUserPresets()
        return imported
    }
    
    func exportAllUserPresets() -> Data? {
        try? JSONEncoder().encode(userPresets)
    }
    
    // MARK: - Reset
    
    func resetToDefaults() {
        currentPreset = BrushDefinition.defaultSmooth
        saveCurrentPreset()
    }
    
    func clearAllUserPresets() {
        userPresets.removeAll()
        saveUserPresets()
    }
}
