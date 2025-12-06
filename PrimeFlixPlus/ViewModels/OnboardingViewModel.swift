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
    
    // --- State ---
    @Published var step: OnboardingStep = .intro
    @Published var selectedMoods: Set<String> = []
    @Published var selectedGenres: Set<String> = []
    
    // --- Search State ---
    @Published var searchQuery: String = ""
    @Published var searchResults: [TmdbSearchResult] = []
    @Published var manualFavorites: [TmdbSearchResult] = []
    @Published var isSearching: Bool = false
    
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
        // Initialize the sub-repository using the same container
        self.preferencesRepo = UserPreferencesRepository(container: repository.container)
        
        setupSearchSubscription()
    }
    
    private func setupSearchSubscription() {
        $searchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self = self, !query.isEmpty else {
                    self?.searchResults = []
                    return
                }
                Task { await self.performSearch(query) }
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
            case .done: break // Handled by View callback
            }
        }
    }
    
    func toggleMood(_ mood: String) {
        if selectedMoods.contains(mood) {
            selectedMoods.remove(mood)
        } else {
            selectedMoods.insert(mood)
        }
    }
    
    func toggleGenre(_ genre: String) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else {
            selectedGenres.insert(genre)
        }
    }
    
    func addFavorite(_ item: TmdbSearchResult) {
        if !manualFavorites.contains(item) {
            withAnimation {
                manualFavorites.append(item)
            }
            // Clear search to allow adding another
            searchQuery = ""
            searchResults = []
        }
    }
    
    func removeFavorite(_ item: TmdbSearchResult) {
        withAnimation {
            manualFavorites.removeAll { $0 == item }
        }
    }
    
    // MARK: - Search Logic
    
    private func performSearch(_ query: String) async {
        self.isSearching = true
        
        // Parallel Fetch: Movies & TV
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
            
            // Interleave results for variety
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
    
    // MARK: - Processing & Completion
    
    private func startProcessing() {
        step = .processing
        
        Task {
            // 1. Save Moods & Genres
            preferencesRepo?.completeOnboarding(
                moods: Array(selectedMoods),
                genres: Array(selectedGenres)
            )
            
            // 2. Save Manual Favorites (Loose Mode)
            // We treat these as "Loved" which implies "Watched" logic for sequels
            for item in manualFavorites {
                preferencesRepo?.saveTasteItem(
                    tmdbId: item.id,
                    title: item.title,
                    type: item.type, // "movie" or "tv" maps correctly
                    status: "loved"
                )
            }
            
            // 3. Artificial Delay for UX ("Personalizing...")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            // 4. Trigger "Fresh Content" Re-evaluation
            // Since we just seeded "Watched" items, we want the app to look for sequels immediately.
            // This requires the ChannelRepository logic update (next step).
            // For now, we notify the main Repository that something changed.
            await MainActor.run {
                repository?.objectWillChange.send()
                self.step = .done
            }
        }
    }
}
