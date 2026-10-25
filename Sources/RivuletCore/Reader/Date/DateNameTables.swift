// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `time/format.go`
// (`longDayNames`, `shortDayNames`, `shortMonthNames`, `longMonthNames`); adapted for Swift.

import Foundation

/// The day and month name tables `lookup` matches a value against, in the order Go lists them,
/// which is the order a match is decided in.
enum DateNameTables {
    static let longDayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
        "Saturday"]

    static let shortDayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static let shortMonthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
        "Nov", "Dec"]

    static let longMonthNames = ["January", "February", "March", "April", "May", "June", "July",
        "August", "September", "October", "November", "December"]
}
