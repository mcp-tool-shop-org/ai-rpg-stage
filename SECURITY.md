# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| `main`  | Yes       |

This repository has no tagged releases yet; `main` is the supported line.

## Reporting a Vulnerability

Email: **64996768+mcp-tool-shop@users.noreply.github.com**

Include:
- Description of the vulnerability
- Steps to reproduce
- Commit affected
- Potential impact

Please report privately rather than opening a public issue.

### Response timeline

| Action | Target |
|--------|--------|
| Acknowledge report | 48 hours |
| Assess severity | 7 days |
| Release fix | 30 days |

## Scope

`ai-rpg-stage` is a Godot 4 client. It renders a simulation it does not own.

**Network surface.** The stage opens exactly one **outbound** TCP connection, to
a host and port the operator passes to `NetworkClient.attach(host, port)`. There
is no default endpoint, no service discovery, and no inbound listener — nothing
here accepts a connection.

**The trust boundary is the engine.** By design the stage holds no rules and
advances no clock: it submits intent and draws what comes back. It therefore does
**not** validate simulation content, and cannot — a client that second-guesses the
simulation becomes a second source of truth, which is the specific failure this
architecture exists to prevent. The consequence for security is that **whoever
controls the endpoint controls what is rendered**. Point the stage only at an
`ai-rpg-engine` instance you trust, on a network you trust. Treat the endpoint as
you would a database connection string.

**What it does not do:**
- No credentials are read, stored, or transmitted — the wire protocol is unauthenticated by design and assumes a trusted local endpoint
- No telemetry is collected or sent
- No code is downloaded or executed at runtime
- Writes only to Godot's own user data directory

**Out of scope:** vulnerabilities in a malicious or compromised engine endpoint.
That is the engine's boundary, not the stage's — report those against
[`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine).
