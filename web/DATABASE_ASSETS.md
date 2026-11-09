# Browser database assets

These assets are shipped with the site so offline storage does not depend on
third-party CDNs at runtime.

| File | Source |
| --- | --- |
| `drift_worker.js` | [Drift 2.28.2 release](https://github.com/simolus3/drift/releases/tag/drift-2.28.2) |
| `sqlite3.wasm` | [sqlite3 2.9.4 release](https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-2.9.4) |

Drift is MIT licensed, see [Drift LICENSE](https://github.com/simolus3/drift/blob/drift-2.28.2/LICENSE).
The Dart sqlite3 package is MIT licensed, see
[sqlite3 LICENSE](https://github.com/simolus3/sqlite3.dart/blob/sqlite3-2.9.4/LICENSE).
The underlying SQLite implementation is in the public domain.

Keep these versions aligned with `pubspec.yaml` and the resolved `pubspec.lock`
when upgrading. `database_connection_web.dart` opens these same-origin assets.
