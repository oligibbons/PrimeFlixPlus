import Foundation
import Combine
import SwiftUI
import CoreData

@MainActor
class OnboardingViewModel: ObservableObject {
    
    enum OnboardingStep {
        case intro
        case moods
        case genres
        case favorites // Manual Entry
        case processing
        case done
    }
    
    // --- Helper Model for Local State ---
    struct UserFavorite: Identifiable, Equatable {
        let item: TmdbSearchResult
        var isSuper: Bool = false
        var id: Int { item.id }
        
        static func == (lhs: UserFavorite, rhs: UserFavorite) -> Bool {
            return lhs.id == rhs.id && lhs.isSuper == rhs.isSuper
        }
    }
    
    // --- State ---
    @Published var step: OnboardingStep = .intro
    @Published var selectedMoods: Set<String> = []
    @Published var selectedGenres: Set<String> = []
    
    // --- Search State ---
    @Published var searchQuery: String = ""
    @Published var searchResults: [TmdbSearchResult] = []
    @Published var isSearching: Bool = false
    
    // --- Favorites State ---
    @Published var manualFavorites: [UserFavorite] = []
    
    // UI Triggers
    @Published var editingFavorite: UserFavorite? = nil
    @Published var showEditDialog: Bool = false
    
    // --- Data Definition ---
    let availableMoods = [
        "Adrenaline", "Chill", "Dark", "Feel-Good",
        "Romantic", "Thoughtful", "Scary", "Epic"
    ]
    
    let availableGenres = [
        "Action", "Adventure", "Animation", "Comedy", "Crime",
        "Documentary", "Drama", "Family", "Fantasy", "History",
        "Horror", "Music", "Mystery", "Romance", "Sci-Fi",
        "Thriller", "War", "Western"
    ]
    
    // --- Dependencies ---
    private var preferencesRepo: UserPreferencesRepository?
    private let tmdbClient = TmdbClient()
    private var repository: PrimeFlixRepository?
    private var cancellables = Set<AnyCancellable>()
    
    // --- Helper Model for Unified Search ---
    struct TmdbSearchResult: Identifiable, Equatable {
        let id: Int
        let title: String
        let type: String // "movie" or "tv"
        let year: String
        let posterUrl: URL?
        let overview: String
        
        static func == (lhs: TmdbSearchResult, rhs: TmdbSearchResult) -> Bool {
            return lhs.id == rhs.id && lhs.type == rhs.type
        }
    }
    
    // MARK: - Configuration
    
    func configure(repository: PrimeFlixRepository) {
        self.repository = repository
        self.preferencesRepo = UserPreferencesRepository(container: repository.container)
        
        setupSearchSubscription()
        loadExistingPreferences()
    }
    
    // NEW: Pre-fill data if user is revisiting settings
    private func loadExistingPreferences() {
        guard let repo = preferencesRepo else { return }
        
        // 1. Load Moods & Genres
        let profile = repo.getProfile()
        if let moods = profile.selectedMoods {
            self.selectedMoods = Set(moods.components(separatedBy: ",").filter { !$0.isEmpty })
        }
        if let genres = profile.selectedGenres {
            self.selectedGenres = Set(genres.components(separatedBy: ",").filter { !$0.isEmpty })
        }
        
        // 2. Load Favorites
        // We fetch 'loved' and 'super_loved' items to populate the list
        let items = repo.getTasteItems()
        self.manualFavorites = items.filter { $0.status == "loved" || $0.status == "super_loved" }.compactMap { item in
            guard let title = item.title, let type = item.mediaType else { return nil }
            
            // Reconstruct TmdbSearchResult from Core Data
            let searchResult = TmdbSearchResult(
                id: Int(item.tmdbId),
                title: title,
                type: type,
                year: "", // Not persisted, but acceptable for this list
                posterUrl: item.posterPath.map { URL(string: "https://image.tmdb.org/t/p/w200\($0)")! },
                overview: ""
            )
            
            return UserFavorite(item: searchResult, isSuper: item.status == "super_loved")
        }
    }
    
    private func setupSearchSubscription() {
        $searchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.isEmpty {
                    self.searchResults = []
                } else {
                    Task { await self.performSearch(query) }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    func nextStep() {
        withAnimation(.easeInOut(duration: 0.5)) {
            switch step {
            case .intro: step = .moods
            case .moods: step = .genres
            case .genres: step = .favorites
            case .favorites: startProcessing()
            case .processing: step = .done
            case .done: break
            }
        }
    }
    
    func toggleMood(_ mood: String) {
        if selectedMoods.contains(mood) { selectedMoods.remove(mood) }
        else { selectedMoods.insert(mood) }
    }
    
    func toggleGenre(_ genre: String) {
        if selectedGenres.contains(genre) { selectedGenres.remove(genre) }
        else { selectedGenres.insert(genre) }
    }
    
    // MARK: - Favorites Logic
    
    func addFavorite(_ item: TmdbSearchResult) {
        if !manualFavorites.contains(where: { $0.item.id == item.id }) {
            withAnimation {
                manualFavorites.append(UserFavorite(item: item))
            }
        }
    }
    
    func prepareEdit(_ fav: UserFavorite) {
        self.editingFavorite = fav
        self.showEditDialog = true
    }
    
    func toggleSuperFavorite() {
        guard let target = editingFavorite,
              let index = manualFavorites.firstIndex(where: { $0.id == target.id }) else { return }
        
        withAnimation {
            manualFavorites[index].isSuper.toggle()
        }
        self.editingFavorite = nil
    }
    
    func removeFavorite() {
        guard let target = editingFavorite else { return }
        
        // Remove from UI
        withAnimation {
            manualFavorites.removeAll { $0.id == target.id }
        }
        
        // Also explicitly remove from DB immediately to avoid sync issues if they cancel later?
        // No, we wait for "Finish" to save state, but we should track deletions if we were strict.
        // For now, simpler: The `startProcessing` overwrites/saves.
        // To be safe, let's remove from DB immediately if it exists.
        preferencesRepo?.removeTasteItem(tmdbId: target.id)
        
        self.editingFavorite = nil
    }
    
    // MARK: - Search Logic
    
    private func performSearch(_ query: String) async {
        self.isSearching = true
        
        async let movies = tmdbClient.searchMovie(query: query)
        async let shows = tmdbClient.searchTv(query: query)
        
        do {
            let (mResults, sResults) = try await (movies, shows)
            
            let mappedMovies = mResults.prefix(5).map { m in
                TmdbSearchResult(
                    id: m.id,
                    title: m.title,
                    type: "movie",
                    year: String(m.releaseDate?.prefix(4) ?? ""),
                    posterUrl: m.posterPath.map { URL(string: "https://image.tmdb.org/t/p/w200\($0)")! },
                    overview: m.overview ?? ""
                )
            }
            
            let mappedShows = sResults.prefix(5).map { s in
                TmdbSearchResult(
                    id: s.id,
                    title: s.name,
                    type: "tv",
                    year: String(s.firstAirDate?.prefix(4) ?? ""),
                    posterUrl: s.posterPath.map { URL(string: "https://image.tmdb.org/t/p/w200\($0)")! },
                    overview: s.overview ?? ""
                )
            }
            
            var combined: [TmdbSearchResult] = []
            let maxCount = max(mappedMovies.count, mappedShows.count)
            for i in 0..<maxCount {
                if i < mappedMovies.count { combined.append(mappedMovies[i]) }
                if i < mappedShows.count { combined.append(mappedShows[i]) }
            }
            
            await MainActor.run {
                self.searchResults = combined
                self.isSearching = false
            }
        } catch {
            print("Onboarding Search Error: \(error)")
            self.isSearching = false
        }
    }
    
    // MARK: - Processing
    
    private func startProcessing() {
        step = .processing
        
        Task {
            // 1. Save Moods & Genres
            preferencesRepo?.completeOnboarding(
                moods: Array(selectedMoods),
                genres: Array(selectedGenres)
            )
            
            // 2. Save Manual Favorites
            for fav in manualFavorites {
                preferencesRepo?.saveTasteItem(
                    tmdbId: fav.item.id,
                    title: fav.item.title,
                    type: fav.item.type,
                    status: fav.isSuper ? "super_loved" : "loved",
                    posterPath: fav.item.posterUrl?.path // Save path for UI reload
                )
            }
            
            // 3. UX Delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            // 4. Trigger Refresh
            await MainActor.run {
                repository?.objectWillChange.send()
                self.step = .done
            }
        }
    }
}
