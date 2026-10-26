import Foundation

/// The three scores at one moment, with what each fiche needs to explain them.
public struct HomeScores: Sendable, Equatable {
    public var comfort: ComfortScore?
    public var energy: EnergyScore?
    public var network: NetworkScore?
    /// Nothing measures the internet yet (no internet check in the source).
    public var hasNetworkSource: Bool
    /// An electricity meter reaches the server, even if it has no habit to compare with yet.
    public var hasElectricityMeter: Bool
    /// What Maison noticed, most valuable first.
    public var findings: [Finding]
    /// What the home screen shows under the scores, most urgent first.
    public var highlights: [Highlight]
    /// The price of a kWh and what the day and the month cost, when a price is known.
    public var energyPrice: EnergyPrice?
    public var energyCost: EnergyCost?
    public var computedAt: Date

    public init(
        comfort: ComfortScore? = nil,
        energy: EnergyScore? = nil,
        network: NetworkScore? = nil,
        hasNetworkSource: Bool = false,
        hasElectricityMeter: Bool = false,
        findings: [Finding] = [],
        highlights: [Highlight] = [],
        energyPrice: EnergyPrice? = nil,
        energyCost: EnergyCost? = nil,
        computedAt: Date
    ) {
        self.comfort = comfort
        self.energy = energy
        self.network = network
        self.hasNetworkSource = hasNetworkSource
        self.hasElectricityMeter = hasElectricityMeter
        self.findings = findings
        self.highlights = highlights
        self.energyPrice = energyPrice
        self.energyCost = energyCost
        self.computedAt = computedAt
    }
}
