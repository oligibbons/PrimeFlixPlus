import Foundation
import CoreData
import Combine
import SwiftUI

@MainActor
class ContinueWatchingViewModel: ObservableObject {
    
    // MARK: - Outputs
    @Published var items: [Channel] = []
    @Published var isLoading: Bool = false
    
    // MARK: - Dependencies
    private var repository: PrimeFlixRepository?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        setupObservers()
        loadContent()
    }
    
    // MARK: - Data Loading
    
    func loadContent() {
        guard let repo = repository else { return }
        self.isLoading = true
        
        // We perform the heavy filtering on a background context to avoid UI stutters
        let bgContext = repo.container.newBackgroundContext()
        
        Task.detached(priority: .userInitiated) {
            await bgContext.perform {
                // 1. Fetch all progress records sorted by last played (newest first)
                let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
                request.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
                
                guard let progressItems = try? bgContext.fetch(request) else {
                    await MainActor.run { self.isLoading = false }
                    return
                }
                
                // 2. Apply Strict 5% - 95% Logic
                // We do this in memory because calculating percentages in NSPredicate is complex/slow
                let validUrls = progressItems.compactMap { item -> String? in
                    let pos = Double(item.position)
                    let dur = Double(item.duration)
                    
                    guard dur > 0 else { return nil }
                    let percentage = pos / dur
                    
                    // The "Goldilocks" Zone: Started (>5%) but not Finished (<95%)
                    if percentage > 0.05 && percentage < 0.95 {
                        return item.channelUrl
                    }
                    return nil
                }
                
                // 3. Fetch corresponding Channels
                // We verify they still exist in the library
                var validChannels: [Channel] = []
                let channelRepo = ChannelRepository(context: bgContext)
                
                for url in validUrls {
                    if let channel = channelRepo.getChannel(by: url) {
                        validChannels.append(channel)
                    }
                }
                
                // 4. Map ObjectIDs for Main Context
                let objectIDs = validChannels.map { $0.objectID }
                
                await MainActor.run {
                    // Re-fetch on main thread using IDs to respect thread safety
                    let viewContext = repo.container.viewContext
                    self.items = objectIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Actions
    
    func removeFromHistory(_ channel: Channel) {
        guard let repo = repository else { return }
        
        // Optimistic UI Update
        withAnimation {
            items.removeAll { $0.url == channel.url }
        }
        
        // Database Delete
        let context = repo.container.newBackgroundContext()
        context.perform {
            let req = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            req.predicate = NSPredicate(format: "channelUrl == %@", channel.url)
            req.fetchLimit = 1
            
            if let object = try? context.fetch(req).first {
                context.delete(object)
                try? context.save()
            }
        }
    }
    
    func playChannel(_ channel: Channel) {
        // Handled by parent view, but we could add tracking logic here if needed
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        // Reload if the user watches something elsewhere in the app
        NotificationCenter.default.publisher(for: NSNotification.Name("WatchProgressUpdated"))
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadContent()
            }
            .store(in: &cancellables)
    }
}
