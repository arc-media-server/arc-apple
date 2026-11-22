/// Apple TV already opens the picker on launch. Only a valid local opt-in skips it.
public enum LaunchProfile {
    public static func directProfile(status: AuthStatus, automaticId: String?, fresh: Bool) -> Profile? {
        guard fresh else { return status.profile }
        guard status.signedIn, let automaticId, !automaticId.isEmpty else { return nil }
        return status.profiles.first { $0.id == automaticId && !$0.hasPin }
    }
}
