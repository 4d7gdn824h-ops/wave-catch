import XCTest
import WaveCatchCore

func shells(_ count: Int) -> [ObjectKind] {
    Array(repeating: .shell, count: count)
}

func advance(_ game: GameSession, to target: Double, dt: Double = 0.01) -> [GameEvent] {
    var events: [GameEvent] = []
    var steps = 0
    while game.time < target - 1e-9 && !game.isGameOver && steps < 200000 {
        if game.hitStopRemaining > 0 {
            events += game.tick(dt: min(dt, max(game.hitStopRemaining, 0.001)))
        } else {
            let step = min(dt, target - game.time)
            events += game.tick(dt: step)
        }
        steps += 1
    }
    return events
}

func burnHitStop(_ game: GameSession) -> [GameEvent] {
    var events: [GameEvent] = []
    var steps = 0
    while game.hitStopRemaining > 0 && steps < 30 {
        events += game.tick(dt: 0.03)
        steps += 1
    }
    return events
}

func followCatchables(_ game: GameSession) {
    if let lane = game.suggestedLane() {
        game.setPosition(lane)
    }
}

func play(_ game: GameSession, for duration: Double, dt: Double = 0.05, steer: (GameSession) -> Void) -> [GameEvent] {
    var events: [GameEvent] = []
    let end = game.time + duration
    var steps = 0
    while game.time < end && !game.isGameOver && steps < 200000 {
        steer(game)
        if game.hitStopRemaining > 0 {
            events += game.tick(dt: min(0.03, game.hitStopRemaining))
        } else {
            events += game.tick(dt: dt)
        }
        steps += 1
    }
    return events
}

func missSoonestCatchable(_ game: GameSession) -> [GameEvent] {
    var events: [GameEvent] = []
    var steps = 0
    while !game.liveObjects.contains(where: { $0.kind.isCatchable }) && !game.isGameOver && steps < 8000 {
        events += game.tick(dt: 0.02)
        steps += 1
    }
    guard let target = game.liveObjects
        .filter({ $0.kind.isCatchable })
        .min(by: { $0.arrivalTime < $1.arrivalTime })
    else { return events }
    game.setPosition(target.lane.opposite)
    let deadline = target.arrivalTime + Feel.lateGrace + 0.03
    while game.time < deadline && !game.isGameOver && steps < 16000 {
        let batch = game.tick(dt: 0.01)
        events += batch
        steps += 1
        let lostLife = batch.contains { event in
            if case .missed(_, _, _, true) = event { return true }
            if case .gameOver = event { return true }
            return false
        }
        if lostLife { break }
    }
    return events
}

func firstSpawn(_ game: GameSession) -> (event: GameEvent, all: [GameEvent]) {
    var events: [GameEvent] = []
    var steps = 0
    while steps < 1000 {
        let batch = game.tick(dt: 0.02)
        events += batch
        if let spawned = batch.first(where: { if case .spawned = $0 { return true }; return false }) {
            return (spawned, events)
        }
        steps += 1
    }
    XCTFail("spawner produced no object")
    return (.gameOver(score: 0, bestCombo: 0), events)
}

func survives(_ game: GameSession) {
    followCatchables(game)
    let live = game.liveObjects
    if let jelly = live
        .filter({ $0.kind == .jellyfish && $0.lane == game.position })
        .min(by: { $0.arrivalTime < $1.arrivalTime })
    {
        let catchableFirst = live.contains {
            $0.kind.isCatchable && $0.lane == game.position && $0.arrivalTime < jelly.arrivalTime - 0.08
        }
        if !catchableFirst && jelly.arrivalTime - game.time < 0.55 {
            if let away = Lane.allCases.first(where: { candidate in
                candidate != jelly.lane && !live.contains {
                    $0.kind == .jellyfish && $0.lane == candidate && $0.arrivalTime - game.time < 0.7
                }
            }) {
                game.setPosition(away)
            }
        }
    }
}
