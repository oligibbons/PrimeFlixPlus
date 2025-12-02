import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var repository: PrimeFlixRepository
    
    var onPlayChannel: (Channel) -> Void
    var onAddPlaylist: () -> Void
    var onSettings: () -> Void
    
    @FocusState private var focusedCategory: String?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.selectedPlaylist == nil {
                // Playlist Selection View
                VStack(spacing: 40) {
                    Text("Who is watching?").font(.title).foregroundColor(.white)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 40) {
                        Button(action: onAddPlaylist) {
                            VStack {
                                Image(systemName: "plus").font(.system(size: 50))
                                Text("Add Profile")
                            }.frame(width: 300, height: 200)
                        }.buttonStyle(.card)
                        
                        ForEach(viewModel.playlists) { playlist in
                            Button(action: { viewModel.selectPlaylist(playlist) }) {
                                VStack {
                                    Image(systemName: "person.tv.fill").font(.system(size: 50))
                                    Text(playlist.title)
                                }.frame(width: 300, height: 200)
                            }.buttonStyle(.card)
                        }
                    }.padding(100)
                }
            } else {
                // Dashboard View
                HStack(alignment: .top, spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            // Tabs
                            HStack(spacing: 30) {
                                tabButton(title: "SERIES", type: .series)
                                tabButton(title: "MOVIES", type: .movie)
                                tabButton(title: "LIVE TV", type: .live)
                                Spacer()
                                Button(action: onSettings) { Image(systemName: "gearshape") }.buttonStyle(.plain)
                            }.padding(.top, 20).padding(.horizontal, 50)
                            
                            // Categories
                            ScrollView(.horizontal) {
                                HStack(spacing: 20) {
                                    ForEach(viewModel.categories, id: \.self) { category in
                                        Button(category) { viewModel.selectCategory(category) }
                                            .buttonStyle(.card)
                                            .focused($focusedCategory, equals: category)
                                    }
                                }.padding(.horizontal, 50).padding(.vertical, 20)
                            }
                            
                            // Grid
                            if viewModel.isLoading {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 40)], spacing: 40) {
                                    ForEach(viewModel.displayedChannels) { channel in
                                        // Channel Card
                                        Button(action: { onPlayChannel(channel) }) {
                                            AsyncImage(url: URL(string: channel.cover ?? "")) { img in
                                                img.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Color.gray
                                            }
                                        }
                                        .buttonStyle(.card)
                                        .frame(width: 180, height: 270)
                                        .overlay(Text(channel.title).lineLimit(1).font(.caption), alignment: .bottom)
                                    }
                                }.padding(.horizontal, 50)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.configure(repository: repository) }
    }
    
    // Fixed: Removed @Composable attribute
    private func tabButton(title: String, type: StreamType) -> some View {
        Button(action: { viewModel.selectTab(type) }) {
            Text(title).foregroundColor(viewModel.selectedTab == type ? .cyan : .gray)
        }.buttonStyle(.plain)
    }
}
