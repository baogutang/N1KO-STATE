# WP0 Agent compatibility spike

- Run date: 2026-07-15T09:13:21Z
- Upstream: `https://github.com/erha19/ping-island.git`
- Commit: `da130d679e830894240e926184d29751dfd2def1`
- Compiler: `Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)`
- Target: `arm64-apple-macosx12.0`
- Swift language mode: 5

## Slice

The spike typechecks the pinned Agent models, client-profile boundary, Claude conversation parser,
Codex rollout parser and thread snapshot, plus the exact association and usage cache stores. Small
support excerpts are extracted from the same commit only to avoid pulling the socket server and live
session singleton into the spike.

## Result

- Unmodified slice: expected failure at `PingIsland/Services/Codex/CodexRolloutParser.swift:531`.
- Incompatible API: `String.split(separator: "__", omittingEmptySubsequences: false)` resolves to
  the multi-character overload that is macOS 13+.
- macOS 12 adaptation: replace that call with `components(separatedBy: "__")`; the complete
  selected model/parser group then typechecks.
- Store slice: the unmodified association and usage cache stores typecheck for macOS 12 behind
  boundary stubs.
- Backport estimate: low for this representative slice (one parser call plus N1KO-owned runtime
  paths); broader WP3 ports still require per-file availability checks.

## Decision evidence

This spike does not justify raising N1KO-STATE's minimum from macOS 12. It supports preserving macOS
12 and isolating newer APIs behind adapters or availability checks.
