import Foundation

/// The source repository a build offers (AGPL-3.0 section 13): its
/// `SHIORI_SOURCE_URL` when that's a plain http(s) address, no credentials
/// or spaces; otherwise nothing is shown. search-core's `sourceLink` is the
/// twin, with the same tests.
public enum SourceLink {
    public static let license = "GNU AGPL-3.0-or-later"

    public static func url(_ raw: String?) -> URL? {
        let text = (raw ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace), !text.hasPrefix("$("),
            let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil
        else { return nil }
        return URL(string: text)
    }
}
