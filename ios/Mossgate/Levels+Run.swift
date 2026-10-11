import Foundation

/// Assembling a run's gate list.
///
/// Kept apart from the level data itself so the data stays readable: `Levels.swift`
/// is a list of hand-built gates, this is the rule for turning that list plus the
/// generator into the six gates of every world.
extension Levels {

    /// Every gate in the game. A constant — the run seed changes the LAYOUTS, never
    /// how many there are.
    static var totalGates: Int { Worlds.all.count * Worlds.gatesPerWorld }

    /// The gates of one world, in order, for a given run seed.
    ///
    /// Worlds 0 and 1 open with their authored gates, which matters because they are
    /// the ones that teach: Wick Road shows you the mover, Tinder Hall the bramble.
    /// A generated gate would teach nothing on purpose. Everything after the
    /// authored run is built fresh, so the back half of the game is new every time.
    static func build(seed: Int) -> [Level] {
        var out: [Level] = []
        out.reserveCapacity(totalGates)
        for world in Worlds.all {
            let authoredHere = authored.filter { $0.world == world.id }
            for slot in 0..<Worlds.gatesPerWorld {
                if slot < authoredHere.count {
                    out.append(authoredHere[slot])
                } else {
                    out.append(LevelGen.gate(world: world.id, slot: slot, seed: seed))
                }
            }
        }
        return out
    }

    /// The current run's gates.
    static var all: [Level] { build(seed: SettingsStore.shared.runSeed) }

    /// Where a gate sits in the flat progress arrays. Stable across runs, which is
    /// what makes "world complete" meaningful when the layouts are not.
    static func gateKey(world: Int, slot: Int) -> Int {
        world * Worlds.gatesPerWorld + slot
    }

    static func world(of key: Int) -> Int { key / Worlds.gatesPerWorld }
    static func slot(of key: Int) -> Int { key % Worlds.gatesPerWorld }
}
