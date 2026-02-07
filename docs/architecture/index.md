# Architecture

TypedBus is a small library with a clear internal structure. This section explains the core design decisions.

- [Publish Flow](publish-flow.md) — what happens when you call `publish`
- [Concurrency Model](concurrency-model.md) — fiber-only design with Async
- [Configuration Cascade](configuration-cascade.md) — three-tier parameter resolution
