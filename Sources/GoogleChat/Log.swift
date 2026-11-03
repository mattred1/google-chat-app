// Google Chat for macOS
// Copyright (C) 2026 Bas Peters
//
// This program is free software: you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
// even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program. If not,
// see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Diagnostic logging. Messages that contain conversation data, message ids, page URLs or notification
/// payloads are only written when verbose logging is enabled, because they end up in `log show` and in
/// sysdiagnoses. Failures are logged with `NSLog` directly and always appear.
enum Log {
    static var isVerbose: Bool { UserDefaults.standard.bool(forKey: "VerboseLogging") }

    static func debug(_ message: @autoclosure () -> String) {
        guard isVerbose else { return }
        NSLog("%@", message())
    }
}
