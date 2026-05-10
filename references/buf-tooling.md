# Buf Tooling Reference

## Installation

```bash
# macOS
brew install bufbuild/buf/buf

# npm (for CI/CD)
npm install -D @bufbuild/buf

# Direct
curl -sSL "https://github.com/bufbuild/buf/releases/latest/download/buf-$(uname -s)-$(uname -m)" -o /usr/local/bin/buf && chmod +x /usr/local/bin/buf
```

## buf.yaml — Module Configuration

```yaml
# v2 format (recommended)
version: v2
modules:
  - path: proto
    name: buf.build/myorg/myapis  # optional: BSR module name

# Lint rules
lint:
  use:
    - STANDARD                    # recommended baseline
  except:
    - FIELD_LOWER_SNAKE_CASE      # if you need exceptions
  enum_zero_value_suffix: _UNSPECIFIED
  rpc_allow_same_request_response: false
  rpc_allow_google_protobuf_empty_requests: true
  rpc_allow_google_protobuf_empty_responses: true

# Breaking change detection
breaking:
  use:
    - FILE                        # strictest: per-file compatibility
    # Alternatives: PACKAGE, WIRE, WIRE_JSON
```

### Lint Rule Categories

| Category | Description |
|---|---|
| `STANDARD` | Recommended rules — covers naming, structure, best practices |
| `MINIMAL` | Minimal rules — only critical issues |
| `BASIC` | Basic structural rules |
| `DEFAULT` | Legacy alias for STANDARD |
| `COMMENTS` | Require comments on services, RPCs, messages |
| `UNARY_RPC` | Require unary RPCs (no streaming) |

### Key Individual Lint Rules

```yaml
lint:
  use:
    - STANDARD
  # Commonly toggled rules:
  # - PACKAGE_VERSION_SUFFIX        # require v1, v2, etc.
  # - SERVICE_SUFFIX                # require Service suffix
  # - RPC_REQUEST_STANDARD_NAME     # require GetUserRequest pattern
  # - RPC_RESPONSE_STANDARD_NAME    # require GetUserResponse pattern
  # - ENUM_VALUE_PREFIX             # enum values prefixed with enum name
  # - ENUM_ZERO_VALUE_SUFFIX        # first enum value ends with _UNSPECIFIED
```

## buf.gen.yaml — Code Generation

### Polyglot Configuration (Go + TypeScript + Python)

```yaml
version: v2
clean: true
inputs:
  - directory: proto
managed:
  enabled: true
  override:
    # Go package mapping
    - file_option: go_package_prefix
      value: github.com/myorg/myproject/gen/go

plugins:
  # ─── Go ───
  - remote: buf.build/protocolbuffers/go
    out: gen/go
    opt: paths=source_relative
  - remote: buf.build/connectrpc/go
    out: gen/go
    opt: paths=source_relative

  # ─── TypeScript (Connect-ES v2) ───
  - local: protoc-gen-es
    out: gen/ts
    opt:
      - target=ts

  # ─── Python ───
  - remote: buf.build/protocolbuffers/python
    out: gen/python
  - remote: buf.build/protocolbuffers/pyi
    out: gen/python
  - remote: buf.build/connectrpc/python
    out: gen/python

  # ─── connect-query (optional, local plugin) ───
  # - local: protoc-gen-connect-query
  #   out: gen/ts
  #   opt:
  #     - target=ts
```

### TypeScript-only configuration matching the official examples

The official Connect-ES examples use a **local** `protoc-gen-es` plugin plus `clean: true` so stale generated files are removed before regeneration. Prefer that pattern unless you specifically need remote plugins in CI.

```yaml
version: v2
clean: true
inputs:
  - directory: proto
plugins:
  - local: protoc-gen-es
    out: src/gen
    opt:
      - target=ts
```

Add connect-query only when the app actually uses TanStack Query:

```yaml
version: v2
clean: true
inputs:
  - directory: proto
plugins:
  - local: protoc-gen-es
    out: src/gen
    opt:
      - target=ts
  - local: protoc-gen-connect-query
    out: src/gen
    opt:
      - target=ts
```

### Plugin Options

| Plugin | Key Options |
|---|---|
| `protocolbuffers/go` | `paths=source_relative` — flat output structure |
| `connectrpc/go` | `paths=source_relative` — generates `_connect.go` files |
| `protoc-gen-es` | `target=ts` (TS), `target=js+dts` (JS + declarations); generates messages and service definitions into `*_pb.ts` |
| `protoc-gen-connect-query` | `target=ts` — optional local plugin for TanStack Query helpers in `*_connectquery.ts` |

### Local Plugins (alternative to remote)

```yaml
plugins:
  - local: protoc-gen-go
    out: gen/go
    opt: paths=source_relative
  - local:
      - npx
      - -y
      - @bufbuild/protoc-gen-es
    out: gen/ts
    opt:
      - target=ts
  - local:
      - npx
      - -y
      - @connectrpc/protoc-gen-connect-query
    out: gen/ts
    opt:
      - target=ts
```

## Common Commands

```bash
# Generate code
buf generate

# Lint protos
buf lint
buf lint --error-format=json   # machine-readable

# Check breaking changes
buf breaking --against '.git#branch=main'
buf breaking --against 'buf.build/myorg/myapis'  # against BSR

# Format protos
buf format -w                  # format in-place
buf format --diff              # show diff

# Dependency management
buf dep update                 # update buf.lock

# Test with curl (requires reflection)
buf curl http://localhost:8080 \
  --data '{"id": "123"}' \
  --schema proto \
  myapp.v1.UserService/GetUser
```

## BSR (Buf Schema Registry)

```bash
# Login
buf registry login

# Push module
buf push

# Add dependency
# In buf.yaml:
deps:
  - buf.build/googleapis/googleapis
  - buf.build/grpc-ecosystem/grpc-gateway

# Update lock file
buf dep update

# Export schema
buf export buf.build/myorg/myapis -o ./exported
```

## Breaking Change Detection

### Policy Levels

| Policy | Description | Use Case |
|---|---|---|
| `FILE` | Per-file compatibility, strictest | Public APIs |
| `PACKAGE` | Per-package compatibility | Internal APIs |
| `WIRE` | Wire format compatibility only | Performance-critical |
| `WIRE_JSON` | Wire + JSON compatibility | REST/JSON consumers |

### Common Breaking Changes Detected

- Removing or renaming a field/message/service/RPC
- Changing a field number or type
- Moving a field in/out of a oneof
- Changing stream type of an RPC
- Changing a field from optional to required

```bash
# CI integration
buf breaking --against '.git#branch=main' --error-format=json

# Against specific git ref
buf breaking --against '.git#tag=v1.0.0'

# Against BSR
buf breaking --against 'buf.build/myorg/myapis:v1'
```

## Project Structure (Polyglot)

```text
project/
├── buf.yaml                    # module config
├── buf.gen.yaml                # codegen config
├── buf.lock                    # dependency lock
├── proto/                      # proto sources
│   └── myapp/
│       └── v1/
│           ├── user.proto
│           └── common.proto
├── gen/                        # generated code
│   ├── go/
│   │   └── myapp/v1/
│   ├── ts/
│   │   └── myapp/v1/
│   └── python/
│       └── myapp/v1/
├── backend/                    # Go/Python service
└── frontend/                   # React/Angular app
```

## CI/CD Integration

```yaml
# GitHub Actions
- uses: bufbuild/buf-action@v1
  with:
    setup_only: true    # just install buf
- run: buf lint
- run: buf breaking --against '.git#branch=main'
- run: buf generate
```

## Managed Mode

Managed mode auto-sets file options so you don't need them in protos:

```yaml
# buf.gen.yaml
managed:
  enabled: true
  override:
    # Set go_package for all files
    - file_option: go_package_prefix
      value: github.com/myorg/project/gen/go
    # Set java_package
    - file_option: java_package_prefix
      value: com.myorg.project
    # Per-module overrides
    - file_option: go_package_prefix
      module: buf.build/googleapis/googleapis
      value: google.golang.org/genproto
```

This eliminates `option go_package = "..."` from your proto files.

### When to use managed mode

Use managed mode when:

- you own multiple modules and want Buf to standardize generated package options
- you want to remove repetitive language-specific file options from `.proto` files
- you are generating for Go or Java and need consistent package prefixes

Skip or limit managed mode when:

- the repo already relies on hand-authored per-file options
- a dependency requires explicit package options that differ from your defaults
- you only need a small TypeScript-only setup and managed mode adds noise without solving a real problem
