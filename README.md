# NanoSync

NanoSync is a repository-centric sync and version-control tool for Windows, rebuilt as a Rust workspace.

It currently provides:

- `nanosyncd`: background daemon service
- `nanosync-tui`: terminal UI client
- `nanosync-core`: core domain logic
- `nanosync-protocol`: IPC protocol and message codec

## Current Status

This project is in active rebuild mode.

- The workspace compiles across all crates.
- Core models, IPC command surface, and TUI page skeletons are in place.
- Version-control core behaviors (status/add/commit/branch/stash/diff) are implemented in the current architecture.
- Remote protocol and sync pipeline are partially implemented and still evolving.

See `PROGRESS.md` for the live implementation checklist and `RUST_TUI_REBUILD_SUPERPROMPT.md` for full rebuild constraints.

## Workspace Layout

- `Cargo.toml`: workspace manifest
- `crates/nanosync-core`: core services (repository, remote, sync, VC, automation, logging)
- `crates/nanosync-protocol`: command/event/message protocol
- `crates/nanosyncd`: daemon process and IPC server
- `crates/nanosync-tui`: TUI application
- `PROGRESS.md`: implementation progress log

## Requirements

- Windows 10/11
- Rust toolchain (stable, `cargo` available)
- SQLite runtime support (bundled via Rust dependencies)

## Build

```bash
cargo build --workspace
```

## Run

Start daemon:

```bash
cargo run -p nanosyncd
```

Start TUI (in another terminal):

```bash
cargo run -p nanosync-tui
```

## What Works Today

- Repository registration/import/migration flows
- Remote connection CRUD and connection test entry points
- IPC command handling for repository/remote/sync/VC/automation/logging paths
- TUI navigation and major feature pages
- Basic remote reachability probing:
  - SMB: TCP reachability probe
  - WebDAV: HTTP OPTIONS probe with optional basic auth
  - UNC: UNC path reachability probe
- WebDAV basic file operations:
  - Download (GET), upload (PUT), delete (DELETE)
  - Directory ensure (MKCOL)
  - File existence/info via HEAD
  - Basic directory listing via PROPFIND response parsing
- Safe remote deletion guard:
  - Prevent deleting a remote connection if any repository binding still references it
- Sync state baseline over WebDAV/UNC:
  - `fetch` can pull remote `repository_state.json` and compute non-stub ahead/behind
  - `push` can export/upload local `repository_state.json`
  - `get_sync_status` now derives from actual fetch result
- Sync state baseline over SMB:
  - Supports repository state fetch/push via share-based remote path parsing (e.g. `/public/project`)
- Object transfer baseline:
  - `push` uploads missing local objects to remote `.nanosync/objects`
  - `fetch/pull` downloads missing objects from remote object index (`.nanosync/object_index.json`)
- Pull metadata baseline:
  - Applies remote branch/default-branch state locally as minimal fast-forward metadata update
- Pull working-tree baseline:
  - Applies remote file index to working directory (write/update/delete)
  - Synchronizes local repository object index with remote file index
- Pull safety guard:
  - Refuses pull metadata application when working directory has uncommitted changes

## Known Gaps

- SMB protocol-level deep features (real share enumeration, strict auth verification) are still not fully implemented
- Sync object transfer and robust conflict resolution are still in progress
- Ahead/behind now supports DAG ancestor-distance calculation from local commit graph (best common ancestor by shortest combined distance)
- Pull merge semantics are still minimal (metadata fast-forward + object download), not full content merge yet
- Some clone/sync edge cases remain placeholders
- Integration and end-to-end tests are still limited

## Development Notes

- This is a greenfield Rust rebuild; behavior requirements come from product docs, not legacy Flutter architecture.
- Prioritize correctness and user-visible behavior over backward compatibility during this iteration stage.
- Keep repository business state repository-local; keep software-level state minimal.

## License

MIT. See `LICENSE`.
