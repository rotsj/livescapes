import Foundation

enum SolarPhase: String, CaseIterable, Codable, Identifiable {
    case morning
    case day
    case evening
    case night

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning: return "Morning (Sunrise)"
        case .day: return "Day (High Sun)"
        case .evening: return "Evening (Sunset)"
        case .night: return "Night"
        }
    }

    var systemImage: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }
}

struct SolarPosition {
    let altitudeDegrees: Double
    let azimuthDegrees: Double
    let phase: SolarPhase
}

enum SolarCalculator {
    /// Estimates solar altitude and azimuth using standard NOAA solar position equations.
    static func position(
        date: Date = Date(),
        latitude: Double = 37.7749,
        longitude: Double? = nil
    ) -> SolarPosition {
        // If longitude isn't provided, estimate from local timezone offset (15 deg per hour)
        let tzHours = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600.0
        let lon = longitude ?? (tzHours * 15.0)

        let calendar = Calendar(identifier: .gregorian)
        var utcCal = calendar
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = utcCal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        let dayOfYear = Double(utcCal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let hourUTC = Double(comps.hour ?? 12)
            + Double(comps.minute ?? 0) / 60.0
            + Double(comps.second ?? 0) / 3600.0

        // Fractional year (radians)
        let gamma = (2.0 * .pi / 365.0) * (dayOfYear - 1.0 + (hourUTC - 12.0) / 24.0)

        // Equation of time (minutes)
        let eqTime = 229.18 * (
            0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma)
            - 0.040849 * sin(2 * gamma)
        )

        // Solar declination (radians)
        let decl = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.001480 * sin(3 * gamma)

        let latRad = latitude * .pi / 180.0
        let trueSolarTimeMinutes = (hourUTC * 60.0 + eqTime + 4.0 * lon).truncatingRemainder(dividingBy: 1440.0)
        let normalizedSolarMinutes = trueSolarTimeMinutes < 0 ? trueSolarTimeMinutes + 1440.0 : trueSolarTimeMinutes
        let hourAngleDeg = (normalizedSolarMinutes / 4.0) - 180.0
        let hourAngleRad = hourAngleDeg * .pi / 180.0

        let cosZenith = sin(latRad) * sin(decl) + cos(latRad) * cos(decl) * cos(hourAngleRad)
        let clampedCosZenith = min(1.0, max(-1.0, cosZenith))
        let zenithRad = acos(clampedCosZenith)
        let altitudeDeg = 90.0 - (zenithRad * 180.0 / .pi)

        let sinZenith = sin(zenithRad)
        var azimuthDeg = 180.0
        if abs(sinZenith) > 1e-6 {
            let cosAz = (sin(latRad) * cosZenith - sin(decl)) / (cos(latRad) * sinZenith)
            let azRad = acos(min(1.0, max(-1.0, cosAz)))
            azimuthDeg = hourAngleDeg > 0 ? (azRad * 180.0 / .pi) + 180.0 : 540.0 - (azRad * 180.0 / .pi)
            azimuthDeg = azimuthDeg.truncatingRemainder(dividingBy: 360.0)
        }

        let isMorningHalf = hourAngleDeg < 0
        let phase: SolarPhase
        if altitudeDeg < -4.0 {
            phase = .night
        } else if altitudeDeg < 18.0 {
            phase = isMorningHalf ? .morning : .evening
        } else {
            phase = .day
        }

        return SolarPosition(altitudeDegrees: altitudeDeg, azimuthDegrees: azimuthDeg, phase: phase)
    }
}
