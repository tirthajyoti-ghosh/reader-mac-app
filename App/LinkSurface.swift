import SwiftUI
import WebKit
import AppKit

// MARK: - Second WKWebView (the link surface)

/// Owns the sheet/split web view + its navigation state. Non-persistent data
/// store (privacy). Shared between sheet and split so promoting doesn't reload.
final class LinkWebModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var title = ""
    @Published var host = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    let webView: WKWebView
    private var loadedURL: URL?

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func load(_ url: URL) {
        guard url != loadedURL else { return }
        loadedURL = url
        host = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        title = host
        webView.load(URLRequest(url: url))
    }

    var liveURL: URL? { webView.url ?? loadedURL }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) { sync(wv) }
    func webView(_ wv: WKWebView, didCommit navigation: WKNavigation!) { sync(wv) }
    private func sync(_ wv: WKWebView) {
        canGoBack = wv.canGoBack
        canGoForward = wv.canGoForward
        if let t = wv.title, !t.isEmpty { title = t }
        if let h = wv.url?.host { host = h.replacingOccurrences(of: "www.", with: "") }
    }
}

struct LinkWebView: NSViewRepresentable {
    let model: LinkWebModel
    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Reading area: doc + (sheet | split) link surface

/// The reading pane. The MarkdownWebView lives at a stable position so it stays
/// mounted (scroll preserved) whether a link surface is closed, a sheet, or a
/// split. A single `LinkWebModel` is reused across sheet↔split.
struct ReadingArea: View {
    @ObservedObject var document: Document
    @EnvironmentObject var model: AppModel
    @StateObject private var web = LinkWebModel()
    @State private var docFraction: CGFloat = 0.5   // doc's share of width in split
    var isSelected: Bool = true

    var body: some View {
        let p = model.palette
        let surface = document.surface
        let isSplit = surface?.mode == .split
        let isSheet = surface?.mode == .sheet

        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        MarkdownWebView(document: document, model: model, isSelected: isSelected)
                        if isSelected && model.findVisible { FindBar() }
                    }
                    .frame(maxWidth: .infinity)

                    if isSplit {
                        SplitDivider(palette: p) { dx in
                            let w = max(1, geo.size.width)
                            docFraction = min(0.7, max(0.3, docFraction + dx / w))
                        }
                        LinkPane(web: web, document: document, model: model)
                            .frame(width: max(340, geo.size.width * (1 - docFraction)))
                    }
                }

                if isSheet {
                    p.scrim
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                        .transition(.opacity)
                    SheetView(web: web, document: document, model: model,
                              paneWidth: geo.size.width, onPromote: { promoteToSplit() })
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.move(edge: .trailing))
                }

                // Esc to close (cancelAction); invisible.
                if surface != nil {
                    Button("", action: close).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
                }
            }
            .onChange(of: surface?.url) { _, url in if let url { web.load(url) } }
            .onAppear { if let url = surface?.url { web.load(url) } }
            .animation(.easeOut(duration: 0.22), value: isSheet)
            .animation(.easeOut(duration: 0.2), value: isSplit)
        }
    }

    private func close() { document.surface = nil }
    private func promoteToSplit() {
        if var s = document.surface { s.mode = .split; document.surface = s }
    }
}

// MARK: - Split

private struct LinkPane: View {
    @ObservedObject var web: LinkWebModel
    let document: Document
    let model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(web: web, model: model,
                        showSplitToggle: false, isSplit: true,
                        onClose: { document.surface = nil },
                        onBrowser: { if let u = web.liveURL { NSWorkspace.shared.open(u) } },
                        onPromote: {})
            LinkWebView(model: web)
        }
        .background(model.palette.bg)
        .overlay(model.palette.border.frame(width: 1), alignment: .leading)
    }
}

private struct SplitDivider: View {
    let palette: Palette
    let onDrag: (CGFloat) -> Void
    @State private var hovering = false
    @State private var dragging = false
    @State private var last: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 11)
            .overlay(Rectangle().fill(hovering || dragging ? palette.accent : palette.border)
                .frame(width: hovering || dragging ? 2 : 1))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging { dragging = true; last = 0 }
                    onDrag(v.translation.width - last)
                    last = v.translation.width
                }
                .onEnded { _ in dragging = false; last = 0 })
    }
}

// MARK: - Sheet

private struct SheetView: View {
    @ObservedObject var web: LinkWebModel
    let document: Document
    let model: AppModel
    let paneWidth: CGFloat
    let onPromote: () -> Void
    @State private var extraWidth: CGFloat = 0

    var body: some View {
        let p = model.palette
        let base = min(760, paneWidth * 0.60)
        let width = min(paneWidth - 40, max(360, base + extraWidth))
        HStack(spacing: 0) {
            // left-edge drag handle: drag wider to promote to split
            Rectangle().fill(Color.clear).frame(width: 7)
                .contentShape(Rectangle())
                .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                .gesture(DragGesture()
                    .onChanged { v in extraWidth = max(0, -v.translation.width) }
                    .onEnded { _ in
                        if width > paneWidth * 0.72 { onPromote() }
                        extraWidth = 0
                    })
            VStack(spacing: 0) {
                SheetHeader(web: web, model: model,
                            showSplitToggle: true, isSplit: false,
                            onClose: { document.surface = nil },
                            onBrowser: { if let u = web.liveURL { NSWorkspace.shared.open(u) } },
                            onPromote: onPromote)
                LinkWebView(model: web)
            }
            .frame(width: width)
            .background(p.surface)
            .overlay(p.border.frame(width: 1), alignment: .leading)
            .shadow(color: .black.opacity(0.34), radius: 28, x: -10, y: 0)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Sheet/split header

private struct SheetHeader: View {
    @ObservedObject var web: LinkWebModel
    let model: AppModel
    let showSplitToggle: Bool
    let isSplit: Bool
    let onClose: () -> Void
    let onBrowser: () -> Void
    let onPromote: () -> Void

    var body: some View {
        let p = model.palette
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                SheetIcon(system: "chevron.left", palette: p, enabled: web.canGoBack) { web.goBack() }
                SheetIcon(system: "chevron.right", palette: p, enabled: web.canGoForward) { web.goForward() }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(p.accentSoft)
                Text(String((web.host.first ?? "•")).uppercased())
                    .font(.system(size: 9, weight: .heavy)).foregroundColor(p.accent)
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(web.title).font(.system(size: 13, weight: .semibold)).foregroundColor(p.text)
                    .lineLimit(1).truncationMode(.tail)
                Text(web.host).font(.system(size: 11, design: .monospaced)).foregroundColor(p.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if showSplitToggle {
                SheetIcon(system: "rectangle.split.2x1", palette: p, enabled: true, help: "Open in split", action: onPromote)
            }
            SheetIcon(system: "arrow.up.right", palette: p, enabled: true, help: "Open in browser", action: onBrowser)
            SheetIcon(system: "xmark", palette: p, enabled: true, help: "Close", action: onClose)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .overlay(p.border.frame(height: 1), alignment: .bottom)
        .background(p.surface)
    }
}

private struct SheetIcon: View {
    let system: String
    let palette: Palette
    var enabled: Bool = true
    var help: String = ""
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundColor(!enabled ? palette.border : (hover ? palette.text : palette.muted))
                .background(RoundedRectangle(cornerRadius: 7).fill(hover && enabled ? palette.bg : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .onHover { hover = $0 }
    }
}
