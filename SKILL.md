---
name: connectrpc
description: Use this skill when building, configuring, or debugging ConnectRPC services and clients across Go, Python, and TypeScript, including Buf-based protobuf generation, Connect vs gRPC-Web transport choices, interceptors, and cross-language RPC workflows. Trigger on prompts involving connect-go, connect-es, connect-query, connect-python, buf generate, protobuf services, grpc-web, or Connect-compatible RPC APIs.
license: MIT
metadata:
  version: 1.1.0
  author: Owen Adirah
  tags:
    - grpc
    - protobuf
    - connectrpc
    - buf
    - rpc
    - go
    - python
    - typescript
    - angular
    - react
---

# ConnectRPC

Use this skill to build or fix **proto-first RPC workflows** with ConnectRPC. Default to **Connect protocol + Buf v2 + generated clients/servers**, then load the language-specific reference you need.

## When to Use

Use this skill when:

- wiring a new ConnectRPC service from `.proto` files
- generating Go, TypeScript, or Python stubs with Buf
- deciding between Connect, gRPC, and gRPC-Web
- adding Connect clients to React or Angular apps
- implementing ConnectRPC handlers, interceptors, or error handling
- debugging transport, streaming, CORS, or code generation issues

## Choose the Right Reference

Read only the reference file that matches the task:

- **Go backend** → `references/go.md`
- **TypeScript frontend or Node integration** → `references/typescript.md`
- **Python backend** → `references/python.md`
- **Buf config, linting, breaking checks, generation** → `references/buf-tooling.md`

If the user is asking about:

- **transport choice** → start here, then load `references/typescript.md` or `references/go.md`
- **Python runtime details** → load `references/python.md` immediately
- **generated file names/import paths** → load `references/typescript.md` or `references/python.md`
- **schema/tooling problems** → load `references/buf-tooling.md`

## Core Workflow

- [ ] Define or update the `.proto` schema first
- [ ] Use **Buf v2** for linting, breaking checks, and code generation
- [ ] Generate only the targets needed by the project
- [ ] Pick **Connect protocol** as the default transport unless compatibility requires otherwise
- [ ] Use generated service/client classes instead of handwritten wrappers when available
- [ ] Validate transport, interceptors, and streaming assumptions against the selected language runtime

### Output templates

Use these as the default shape for generated guidance:

```yaml
# buf.yaml
version: v2
modules:
  - path: proto
lint:
  use:
    - STANDARD
breaking:
  use:
    - FILE
```

```bash
buf lint
buf breaking --against '.git#branch=main'
buf generate
```

## Protocol Selection

Choose protocols in this order:

1. **Connect** — default for new work
   - works well in browsers and server-to-server flows
   - easiest to debug when using JSON format

2. **gRPC-Web** — compatibility path
   - use only when the backend does not support Connect protocol
   - browser-friendly, but more constrained

3. **gRPC** — interop path
   - use for existing gRPC-only systems or server-to-server requirements
   - requires stricter HTTP/2 assumptions

## Gotchas

- **TypeScript examples must use current Connect-ES v2 patterns**: `createClient()` and service imports from `*_pb` files
- **Connect-Query is optional**: only use it when the app already benefits from TanStack Query
- **Browsers are not a full streaming environment**: treat server streaming as the reliable browser case
- **Python is a beta / constrained track**: prefer generated `*_connect.py` classes and conservative examples
- **CORS is HTTP middleware work, not interceptor work**
- **Buf v2 is the default**: avoid older `buf.work.yaml` or stale codegen instructions

## Available Scripts

No bundled scripts yet.

If repeated tasks emerge across repos, add scripts such as:

- `scripts/gen.sh` → wraps `buf generate`
- `scripts/validate-proto.sh` → runs `buf lint` and `buf breaking`

If you add scripts later:

- keep them non-interactive
- support `--help`
- make them idempotent
- reference them here with relative paths

## Troubleshooting

- **TS imports look wrong** → load `references/typescript.md` and verify `*_pb` vs `*_connectquery` imports
- **Python example surface seems unfamiliar** → load `references/python.md` and stick to generated classes from `*_connect.py`
- **Browser calls fail with metadata or trailer issues** → check CORS and exposed headers in the server setup
- **Streaming behaves oddly** → verify whether the client/runtime actually supports the stream type you are using
- **Buf generation drifts across languages** → load `references/buf-tooling.md` and verify plugin setup target-by-target

## Best Defaults

- **Schema management**: Buf v2
- **Go server**: generated handler + validation interceptor + standard `net/http`
- **TS browser client**: `createConnectTransport()` + `createClient()`
- **TS query layer**: add `@connectrpc/connect-query` only when using TanStack Query
- **Python server**: generated ASGI application from `*_connect.py`
- **Error handling**: language-native Connect error types with explicit codes

## Reference Docs

- `references/go.md` — Go handlers, interceptors, validation, streaming, testing
- `references/typescript.md` — Connect-ES v2, React, Angular, Connect-Query, stale-pattern warnings
- `references/python.md` — generated ASGI/WSGI apps, generated clients, RequestContext, beta-safe patterns
- `references/buf-tooling.md` — Buf v2 config, generation, breaking checks, managed mode, CI
