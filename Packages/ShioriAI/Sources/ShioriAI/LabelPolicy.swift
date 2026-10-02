import Foundation

/// What automatic labelling does with a page (docs/ai.md):
/// Anthropic applies, Apple suggests.
public enum LabelDecision: Sendable, Equatable {
    /// Write the label now. `agreed`: on the word of the cloud engine and
    /// Apple Intelligence together, rather than the cloud's "high".
    case apply(label: String, by: AIProvider, agreed: Bool)
    /// Offer these for a tap in Suggested Labels: existing labels best
    /// first, or a new one.
    case suggest(labels: [String], newLabel: String?)
    /// Nothing worth offering.
    case nothing
}

public enum LabelPolicy {
    /// Only these engines' "high" answers are applied unattended: Claude's
    /// were accurate enough for that, Apple Intelligence's were not
    /// (measured with shiori-ai-eval), and OpenAI's are unmeasured.
    public static let trusted: Set<AIProvider> = [.anthropic]

    /// `cloud`: the cloud engine's answer, if one was asked. `onDevice`:
    /// Apple Intelligence's, which leads the suggestions; the cloud's
    /// guess follows when it differs, since it's already paid for. When
    /// the two independently pick the same label it's applied whatever the
    /// cloud's confidence.
    ///
    /// `trust` is learnt from the user: a label they keep undoing is only
    /// ever suggested; one whose suggestions they always accept is applied
    /// on a cloud "medium" too.
    public static func decide(cloud: LabelSuggestion?, onDevice: LabelSuggestion?, trust: LabelTrust = LabelTrust()) -> LabelDecision {
        if let cloud, trusted.contains(cloud.provider), let label = cloud.labels.first, !trust.held.contains(label) {
            if cloud.confidence == .high { return .apply(label: label, by: cloud.provider, agreed: onDevice?.labels.first == label) }
            if onDevice?.labels.first == label { return .apply(label: label, by: cloud.provider, agreed: true) }
            if cloud.confidence == .medium, trust.trustedAtMedium.contains(label) {
                return .apply(label: label, by: cloud.provider, agreed: false)
            }
        }
        var ordered: [String] = []
        if let first = onDevice?.labels.first { ordered.append(first) }
        if let first = cloud?.labels.first { ordered.append(first) }
        ordered += onDevice?.labels.dropFirst() ?? []
        var labels: [String] = []
        for label in ordered where !labels.contains(label) { labels.append(label) }
        labels = Array(labels.prefix(2))
        let newLabel = labels.isEmpty ? (onDevice?.newLabel ?? cloud?.newLabel) : nil
        if labels.isEmpty, newLabel == nil { return .nothing }
        return .suggest(labels: labels, newLabel: newLabel)
    }
}
