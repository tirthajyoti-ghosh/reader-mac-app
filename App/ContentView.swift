import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.palette
        HStack(spacing: 0) {
            Sidebar()

            VStack(spacing: 0) {
                TopBar()

                ZStack(alignment: .topTrailing) {
                    p.bg
                    if let doc = model.selectedDocument {
                        MarkdownWebView(document: doc, theme: model.theme, model: model)
                    } else {
                        EmptyState()
                    }
                    if model.findVisible {
                        FindBar()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(p.bg)
        }
        .frame(minWidth: 820, minHeight: 540)
        .background(p.bg)
        .preferredColorScheme(model.theme.colorScheme)
        .ignoresSafeArea()
    }
}
