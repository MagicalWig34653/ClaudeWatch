import Foundation

/// Utilities for handling untrusted text from Claude sessions.
public enum TextSanitizer {
    /// Removes control characters (except newlines/tabs), collapses runs of whitespace
    /// and blank lines, trims, and truncates to `maxLength` characters.
    public static func preview(_ text: String?, maxLength: Int = 240) -> String? {
        guard let text else { return nil }
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\t" {
                scalars.append(scalar == "\t" ? " " : scalar)
            } else if CharacterSet.controlCharacters.contains(scalar) || scalar.properties.generalCategory == .format && scalar != "\u{200D}" {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        let lines = String(scalars)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ") }
            .filter { !$0.isEmpty }
        let cleaned = lines.joined(separator: "\n")
        guard !cleaned.isEmpty else { return nil }
        return truncate(cleaned, to: maxLength)
    }

    public static func truncate(_ text: String, to maxLength: Int) -> String {
        guard text.count > maxLength, maxLength > 1 else { return text }
        return String(text.prefix(maxLength - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// First non-empty line of `text`, sanitized.
    public static func firstLine(_ text: String?, maxLength: Int = 160) -> String? {
        guard let first = preview(text, maxLength: .max)?.split(separator: "\n").first else { return nil }
        return truncate(String(first), to: maxLength)
    }
}
