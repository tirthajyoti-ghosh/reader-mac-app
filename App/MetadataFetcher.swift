import Foundation

/// Resolved metadata for an external link (Open Graph / Twitter card / <title>).
struct LinkMetadata {
    var title: String?
    var site: String?
    var description: String?
    var image: String?
    var domain: String
    var failed: Bool = false

    func peekDictionary(href: String) -> [String: Any] {
        var d: [String: Any] = ["href": href, "kind": "external", "domain": domain]
        d["title"] = (title?.isEmpty == false) ? title! : href
        if let s = site, !s.isEmpty { d["site"] = s }
        if let de = description, !de.isEmpty { d["description"] = de }
        if let im = image, !im.isEmpty { d["image"] = im }
        if failed { d["offline"] = true }
        return d
    }
}

/// Swift-side link resolver — fetches the page and parses social metadata. Doing
/// it Swift-side avoids CORS, and runs ONLY on user hover/click. Session cache.
final class MetadataFetcher {
    static let shared = MetadataFetcher()

    private var cache: [String: LinkMetadata] = [:]
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral   // non-persistent (privacy)
        cfg.timeoutIntervalForRequest = 6
        cfg.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: cfg)
    }

    func fetch(_ url: URL, completion: @escaping (LinkMetadata) -> Void) {
        let key = url.absoluteString
        let domain = (url.host ?? key).replacingOccurrences(of: "www.", with: "")
        if let cached = cache[key] { completion(cached); return }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) Reader/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        session.dataTask(with: req) { [weak self] data, _, _ in
            var meta = LinkMetadata(domain: domain)
            if let data, let html = Self.decode(data.prefix(300_000)) {
                meta = Self.parse(html, base: url, domain: domain)
            } else {
                meta.failed = true
            }
            DispatchQueue.main.async {
                self?.cache[key] = meta
                completion(meta)
            }
        }.resume()
    }

    private static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func parse(_ html: String, base: URL, domain: String) -> LinkMetadata {
        var props: [String: String] = [:]
        if let re = try? NSRegularExpression(pattern: "<meta\\s+([^>]+?)/?>",
                                             options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let ns = html as NSString
            re.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, let r = Range(match.range(at: 1), in: html) else { return }
                let attrs = String(html[r])
                if let key = attr(attrs, "property") ?? attr(attrs, "name"),
                   let content = attr(attrs, "content") {
                    let k = key.lowercased()
                    if props[k] == nil { props[k] = decodeEntities(content) }
                }
            }
        }
        var m = LinkMetadata(domain: domain)
        m.title = props["og:title"] ?? props["twitter:title"] ?? titleTag(html)
        m.description = props["og:description"] ?? props["twitter:description"] ?? props["description"]
        m.site = props["og:site_name"] ?? domain
        if let img = props["og:image"] ?? props["og:image:url"] ?? props["twitter:image"] {
            m.image = absolutize(img, base: base)
        }
        return m
    }

    private static func attr(_ s: String, _ name: String) -> String? {
        firstMatch(s, name + "\\s*=\\s*[\"']([^\"']*)[\"']")
    }
    private static func titleTag(_ html: String) -> String? {
        firstMatch(html, "<title[^>]*>([^<]*)</title>").map(decodeEntities)
    }
    private static func firstMatch(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern,
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, options: [], range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func absolutize(_ src: String, base: URL) -> String {
        src.hasPrefix("http") ? src : (URL(string: src, relativeTo: base)?.absoluteString ?? src)
    }
    private static func decodeEntities(_ s: String) -> String {
        var out = s
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                       "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&nbsp;": " "] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out
    }
}
