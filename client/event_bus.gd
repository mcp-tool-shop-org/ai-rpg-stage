## event_bus.gd — the one place the wire and the scene meet.
##
## An autoload of signals and nothing else (the GDQuest pattern). The reason it
## exists is architectural rather than convenient: without it, every scene that
## wants to know about a simulation event holds a reference to the network client,
## and the day one of those scenes decides to *ask the client a question* instead of
## listening, the stage has started making decisions.
##
## Listening is a one-way relationship. That is the point.
##
## No state lives here. A bus that accumulates state becomes a second world model,
## and the client already has exactly one — `NetworkClient`'s mirror, built only
## from patches the sim sent.
extends Node

# ── Connection lifecycle ──────────────────────────────────────

## The handshake completed. Carries the server's advertised capabilities.
signal connected(server_name: String, engine_version: String, capabilities: Dictionary)

## The socket closed, for any reason. `reason` is empty on an orderly close.
signal disconnected(reason: String)

## The sim refused this client — most likely another client already holds the one
## writer slot. The reason arrives on the wire; it is not inferred from a hangup.
signal refused(reason: String)

## A transport-level fault: connect failure, framing error, protocol violation.
## Never routine. A renderer that ignores these renders a world that stopped.
signal transport_failed(detail: String)

# ── Simulation ────────────────────────────────────────────────

## One advanced tick, exactly as the sim reported it.
signal tick_received(tick: int, hash: String, events: Array, delta: Array)

## One resolved event, re-emitted individually so scenes can bind to the kinds they
## care about without every listener filtering the whole tick.
signal sim_event(event: Dictionary)

## The client's mirror digest or position diverged from the simulation. The stage
## never patches the simulation; instead it logs the first differing pre-image
## offset, replaces its mirror from a fresh snapshot, verifies the new digest, and
## halts play if consecutive resyncs exceed the cap.
signal staleness_detected(detail: String)

## Consecutive resyncs exceeded the cap (or a fresh snapshot still diverged).
## Play stops with a visible error so the client cannot continue on a broken view.
signal session_halted(reason: String)
