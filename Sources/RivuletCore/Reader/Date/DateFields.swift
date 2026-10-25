// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `time/format.go` (`isLeap`,
// `daysIn`, `daysBefore`) and Go's `time.Date`; adapted for Swift.

import Foundation

/// The fields one layout reads, and the arithmetic Go does with them once the value is consumed: a
/// year-day converted to month and day, the day validated against the month, and the fields turned
/// into seconds from the epoch without a `Calendar`, so a layout that reads no date still has an
/// exact value.
struct DateFields {
    var year = 0
    var month = -1
    var day = -1
    var yearDay = -1
    var hour = 0
    var minute = 0
    var second = 0
    var nanoseconds = 0

    /// Wall-time seconds from the epoch, or `nil` when the year-day or the day is out of range,
    /// which is what Go reports as a parse error after the value is consumed.
    func wallSeconds() -> Int64? {
        var month = self.month
        var day = self.day
        var yearDay = self.yearDay

        if yearDay >= 0 {
            var convertedMonth = 0
            var convertedDay = 0
            if Self.isLeap(year) {
                if yearDay == 31 + 29 {
                    convertedMonth = 2
                    convertedDay = 29
                } else if yearDay > 31 + 29 {
                    yearDay -= 1
                }
            }
            if yearDay < 1 || yearDay > 365 {
                return nil
            }
            if convertedMonth == 0 {
                convertedMonth = (yearDay - 1) / 31 + 1
                if Self.daysBefore[convertedMonth] < yearDay {
                    convertedMonth += 1
                }
                convertedDay = yearDay - Self.daysBefore[convertedMonth - 1]
            }
            // A month or a day already read has to agree with the year-day.
            if month >= 0 && month != convertedMonth {
                return nil
            }
            month = convertedMonth
            if day >= 0 && day != convertedDay {
                return nil
            }
            day = convertedDay
        } else {
            if month < 0 {
                month = 1
            }
            if day < 0 {
                day = 1
            }
        }

        if day < 1 || day > Self.daysIn(month: month, year: year) {
            return nil
        }

        return Int64(Self.daysFromCivil(year: year, month: month, day: day)) * 86_400
            + Int64(hour) * 3_600 + Int64(minute) * 60 + Int64(second)
    }

    private static func isLeap(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        month == 2 && isLeap(year) ? 29 : daysBefore[month] - daysBefore[month - 1]
    }

    /// `daysBefore[month]` is the number of days before the month that follows it, which is Go's
    /// table.
    private static let daysBefore = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]

    /// Days from the epoch to a civil date, for the years the layouts can read: the four-digit
    /// pattern reads a year without a sign, so the year is 0 through 9999, and 0 is the year a
    /// layout that reads no date leaves behind. This is Go's proleptic Gregorian count, with the
    /// months ordered from March so that the leap day falls at the end of the counted year.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let countedYear = month <= 2 ? year - 1 : year
        let era = countedYear >= 0 ? countedYear / 400 : (countedYear - 399) / 400
        let yearOfEra = countedYear - era * 400
        let monthIndex = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        return era * 146_097 + yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear - 719_468
    }
}
