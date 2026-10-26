import Foundation

/// The household's comfort range: where it starts, what can be set, and which one Comfort scores against.
/// The range the person entered is kept by the app.
public enum ComfortRangeSetting {
    /// Where the score starts until three days of readings teach the household's own range,
    /// in the unit the server measures in.
    public static func starting(fahrenheit: Bool) -> ClosedRange<Double> { fahrenheit ? 66...72 : 19...22 }

    /// The bounds the person can set a range within, and the step, in the server's unit.
    public static func editable(fahrenheit: Bool) -> (bounds: ClosedRange<Double>, step: Double) {
        fahrenheit ? (50...90, 1) : (10...32, 0.5)
    }

    /// The range Comfort scores against: the one entered, else the one learned, else the starting one.
    public static func resolve(entered: ClosedRange<Double>?, hourlyMeans: [Double],
                               fahrenheit: Bool = false) -> (range: ClosedRange<Double>, origin: ValueOrigin, isStarting: Bool) {
        if let entered { return (entered, .entered, false) }
        if let learned = learned(from: hourlyMeans) { return (learned, .estimated, false) }
        return (starting(fahrenheit: fahrenheit), .estimated, true)
    }

    /// The 10th to 90th percentile of the previous week's hourly means, to the half degree.
    /// `nil` with fewer than three days of readings.
    public static func learned(from hourlyMeans: [Double]) -> ClosedRange<Double>? {
        guard hourlyMeans.count >= 72 else { return nil }
        let lower = (percentile(hourlyMeans, 0.1) * 2).rounded(.down) / 2
        let upper = (percentile(hourlyMeans, 0.9) * 2).rounded(.up) / 2
        return lower < upper ? lower...upper : nil
    }
}
