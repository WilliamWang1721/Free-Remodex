// FILE: RemodexLocalization.swift
// Purpose: Minimal localization helpers for formatted runtime strings.
// Layer: Localization Helper

import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: arguments)
    }
}
