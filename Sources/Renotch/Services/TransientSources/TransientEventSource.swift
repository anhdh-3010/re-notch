// Sources/Renotch/Services/TransientSources/TransientEventSource.swift
import Foundation

/// A pluggable producer of transient peek events. Sources are inert until
/// start(emit:) and must be safe to start/stop repeatedly. Sources may emit
/// from any thread; TransientEventService hops to the main actor.
protocol TransientEventSource: AnyObject {
    func start(emit: @escaping (TransientEvent) -> Void)
    func stop()
}
