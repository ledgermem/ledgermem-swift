# LedgerMem Swift SDK

Official Swift client for the [LedgerMem](https://proofly.dev) memory API.

## Install

Add to `Package.swift`:

```swift
.package(url: "https://github.com/ledgermem/ledgermem-swift.git", from: "0.1.0")
```

Requires Swift 5.9+, iOS 16+, macOS 13+.

## Quickstart

```swift
import LedgerMem

let client = LedgerMemClient(
    apiKey: ProcessInfo.processInfo.environment["LEDGERMEM_API_KEY"]!,
    workspaceId: ProcessInfo.processInfo.environment["LEDGERMEM_WORKSPACE_ID"]!
)

let memory = try await client.create(content: "Shah prefers dark mode in terminals.")
let results = try await client.search(query: "ui preferences", limit: 5)

for hit in results.hits {
    print("\(hit.score) \(hit.content)")
}
```

## Configuration

| Env var | Purpose |
| --- | --- |
| `LEDGERMEM_API_KEY` | Bearer token (required) |
| `LEDGERMEM_WORKSPACE_ID` | Workspace identifier (required) |
| `LEDGERMEM_API_URL` | Override base URL (default `https://api.proofly.dev`) |

## API

| Method | HTTP | Description |
| --- | --- | --- |
| `search(query:limit:actorId:)` | `POST /v1/search` | Semantic + keyword search |
| `create(content:metadata:actorId:)` | `POST /v1/memories` | Store a new memory |
| `update(id:content:metadata:)` | `PATCH /v1/memories/:id` | Patch an existing memory |
| `delete(id:)` | `DELETE /v1/memories/:id` | Remove a memory |
| `list(limit:cursor:actorId:)` | `GET /v1/memories` | Paginated listing |

## License

MIT
