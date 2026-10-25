import Foundation

// Apple Speech lets an app hold at most `AssetInventory.maximumReservedLocales`
// locale reservations (5 on this Mac). Preparing a language reserves its locale,
// the reservation lasts across launches until the app releases it, and releasing
// it lets the system remove that language's assets later (LTR-73). So nothing is
// released until a new language needs the room; then the least recently used other
// reservations make way. Identifiers are compared as `en-US` and `en_US` alike.
nonisolated enum LocaleReservations {
    // The reservations to release before `needed` can be reserved: none when it is
    // already reserved or there is room, otherwise the least recently used others
    // (those never used first). `recentlyUsed` is most recent first. `needed` is
    // never among them.
    static func toRelease(needed: String, reserved: [String], maximum: Int, recentlyUsed: [String]) -> [String] {
        let key = normalized(needed)
        guard !reserved.contains(where: { normalized($0) == key }) else { return [] }
        let excess = reserved.count - (maximum - 1)
        guard excess > 0 else { return [] }
        let rank = Dictionary(recentlyUsed.map(normalized).enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let oldestFirst = reserved.sorted {
            let a = rank[normalized($0)] ?? .max, b = rank[normalized($1)] ?? .max
            return a == b ? $0 < $1 : a > b
        }
        return Array(oldestFirst.prefix(excess))
    }

    // `locale` was just used: it moves to the front, listed once.
    static func used(_ locale: String, in recentlyUsed: [String]) -> [String] {
        [locale] + recentlyUsed.filter { normalized($0) != normalized(locale) }
    }

    static func normalized(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}
