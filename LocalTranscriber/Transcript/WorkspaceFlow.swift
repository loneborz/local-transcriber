import Foundation

// The one rule the sidebar's selection follows. Pure, so it is tested.

nonisolated enum SidebarSelectionRule {
    static func next<S>(current: S?, proposed: S?) -> S? { proposed ?? current }
}
