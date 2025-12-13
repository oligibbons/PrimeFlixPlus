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
        
        // Use a background context for the heavy fetch/filter logic
        let bgContext = repo.container.newBackgroundContext()
        
        Task.detached(priority: .userInitiated) {
            // 1. Fetch & Filter in Background (Synchronous block inside Task)
            var validObjectIDs: [NSManagedObjectID] = []
            
            // Using performAndWait avoids the "async closure in sync context" compiler error
            bgContext.performAndWait {
                // A. Fetch progress history
                let request = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
                request.sortDescriptors = [NSSortDescriptor(key: "lastPlayed", ascending: false)]
                
                guard let progressItems = try? bgContext.fetch(request) else { return }
                
                // B. Filter percentages (5% - 95%)
                let validUrls = progressItems.compactMap { item -> String? in
                    let pos = Double(item.position)
                    let dur = Double(item.duration)
                    
                    guard dur > 0 else { return nil }
                    let percentage = pos / dur
                    
                    if percentage > 0.05 && percentage < 0.95 {
                        return item.channelUrl
                    }
                    return nil
                }
                
                // C. Resolve to Channel ObjectIDs
                let channelRepo = ChannelRepository(context: bgContext)
                for url in validUrls {
                    // FIX: Corrected argument label from 'by:' to 'byUrl:'
                    if let channel = channelRepo.getChannel(byUrl: url) {
                        validObjectIDs.append(channel.objectID)
                    }
                }
            }
            
            // 2. Update UI on Main Actor
            await MainActor.run {
                if validObjectIDs.isEmpty {
                    self.items = []
                } else {
                    let viewContext = repo.container.viewContext
                    self.items = validObjectIDs.compactMap { try? viewContext.existingObject(with: $0) as? Channel }
                }
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Actions
    
    func removeFromHistory(_ channel: Channel) {
        guard let repo = repository else { return }
        
        // Fix: Capture URL string to avoid passing non-Sendable 'Channel' into async/bg context
        let targetUrl = channel.url
        
        // Optimistic UI Update
        withAnimation {
            items.removeAll { $0.url == targetUrl }
        }
        
        // Database Delete
        let context = repo.container.newBackgroundContext()
        context.perform {
            let req = NSFetchRequest<WatchProgress>(entityName: "WatchProgress")
            req.predicate = NSPredicate(format: "channelUrl == %@", targetUrl)
            req.fetchLimit = 1
            
            if let object = try? context.fetch(req).first {
                context.delete(object)
                try? context.save()
            }
        }
    }
    
    func playChannel(_ channel: Channel) {
        // Handled by parent view
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: NSNotification.Name("WatchProgressUpdated"))
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadContent()
            }
            .store(in: &cancellables)
    }
}
