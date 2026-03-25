import Foundation

public enum TypingAuthError: Error, LocalizedError {
    case notEnrolled
    case rejected
    case cancelled
    case lockedOut
    case modelNotFound
    case inferenceFailure
    case keychainError(OSStatus)
    case enrollmentInsufficient(samplesNeeded: Int)

    public var errorDescription: String? {
        switch self {
        case .notEnrolled: return "User has not completed enrollment."
        case .rejected: return "Authentication rejected — typing pattern did not match."
        case .cancelled: return "Authentication was cancelled by the user."
        case .lockedOut: return "Too many failed attempts. Authentication is locked."
        case .modelNotFound: return "ML model not found."
        case .inferenceFailure: return "ML inference failed to produce a result."
        case .keychainError(let status): return "Keychain error: \(status)"
        case .enrollmentInsufficient(let n): return "Need \(n) more enrollment samples."
        }
    }
}
