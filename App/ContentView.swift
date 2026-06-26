import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        HStack(spacing: 0) {
            if model.sidebarVisible {
                Sidebar()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                TopBar()

                HStack(spacing: 0) {
                    ZStack {
                        p.bg
                        if let doc = model.selectedDocument {
                            ReadingArea(document: doc)
                        } else {
                            EmptyState()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    // Right-side outline panel (per-tab; yields to a link split).
                    if let doc = model.selectedDocument {
                        OutlineSlot(document: doc)
                    }
                }
            }
            .background(p.bg)
        }
        .frame(minWidth: 820, minHeight: 540)
        .background(p.bg)
        .preferredColorScheme(model.theme.colorScheme)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.22), value: model.sidebarVisible)
    }
}
