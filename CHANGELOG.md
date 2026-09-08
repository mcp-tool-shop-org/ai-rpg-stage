# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

No tagged release yet. `main` carries the JSON-RPC client, the stage renderer,
and the fixture-driven test suite; history before this file lives in the git log.

### Added

- `SECURITY.md` stating the trust boundary: the stage renders what the engine
  returns and does not validate it, so the endpoint is the security perimeter.
