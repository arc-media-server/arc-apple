import ArcKit
import Foundation

/// Loads a page's answer from Arc: 401 asks for a new sign-in; another failure is logged and
/// comes back as the message to show (`problem`); a cancelled load comes back as neither.
@MainActor
func loadPage<T>(_ app: AppModel, _ what: String, _ load: (ArcAPI) async throws -> T) async -> (value: T?, problem: String?) {
    guard let api = app.api else { return (nil, nil) }
    do {
        return (try await load(api), nil)
    } catch let error as APIError where error.status == 401 {
        app.tokenRefused()
    } catch is CancellationError {
    } catch let error as URLError where error.code == .cancelled {
    } catch {
        ArcLogApp.warn("\(what) failed to load: \(type(of: error))")
        return (nil, L("common.unreachable"))
    }
    return (nil, nil)
}
