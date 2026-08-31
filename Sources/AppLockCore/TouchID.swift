import Foundation
import LocalAuthentication

/// Async result of a biometric attempt.
public enum AuthOutcome {
    case success
    case cancelled
    case failed(Error)
}

/// Wraps the system Touch ID (fingerprint) prompt using the public
/// `LocalAuthentication` framework.
///
/// This is the only place in the app that talks to the Secure Enclave / biometric
/// hardware. The rest of the code just asks "did the owner authenticate?" and never
/// touches keys or secrets itself.
public enum TouchID {

    /// Returns true when the current account can authenticate as the device
    /// owner. This includes Touch ID and the Mac login password fallback.
    public static var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(LAPolicy.deviceOwnerAuthentication, error: &error)
    }

    /// Whether biometric authentication itself is currently available.
    public static var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Prompts the user to authenticate with Touch ID (fingerprint) and reports the result.
    ///
    /// The `localizedReason` string is shown on the system prompt as
    /// "<AppLock> wants to <reason>". It must be short and human readable.
    public static func authenticate(localizedReason: String,
                                    completion: @escaping (AuthOutcome) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        context.localizedCancelTitle = "Cancel"

        // Keep the context alive for the duration of the evaluation.
        context.evaluatePolicy(
            // This policy prefers Touch ID and exposes the system password
            // fallback when biometrics are unavailable or declined.
            LAPolicy.deviceOwnerAuthentication,
            localizedReason: localizedReason
        ) { [context] success, error in
            _ = context
            let outcome: AuthOutcome
            if success {
                outcome = .success
            } else if let error = error as NSError? {
                if error.code == LAError.userCancel.rawValue || error.code == LAError.systemCancel.rawValue {
                    outcome = .cancelled
                } else {
                    outcome = .failed(error)
                }
            } else {
                outcome = .failed(NSError(domain: "AppLock", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "Unknown authentication error"]))
            }
            // LocalAuthentication does not promise a main-queue callback, but
            // callers update AppKit controls and persisted UI state.
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}
