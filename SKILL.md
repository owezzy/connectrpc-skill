---
name: connectrpc
description: Build type-safe RPC services with ConnectRPC across Go, Python, and TypeScript (Angular/React). Use when building ConnectRPC/Connect services, protobuf-based APIs, or buf-managed projects. Trigger phrases include "connectrpc", "connect-go", "connect-es", "buf generate", "protobuf service", "grpc-web", "connect-query".
metadata:
  version: 1.0.0
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

---

## Core Workflow

### 1. Proto-First Design

All ConnectRPC services start with `.proto` files:

```protobuf
syntax = "proto3";
package myapp.v1;

service UserService {
  rpc GetUser(GetUserRequest) returns (GetUserResponse) {}
  rpc ListUsers(ListUsersRequest) returns (stream ListUsersResponse) {}
}

message GetUserRequest {
  string id = 1;
}
message GetUserResponse {
  User user = 1;
}
message User {
  string id = 1;
  string name = 2;
  string email = 3;
}
```

### 2. Code Generation with Buf

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

```yaml
# buf.gen.yaml — polyglot config
version: v2
plugins:
  # Go backend
  - remote: buf.build/connectrpc/go
    out: gen/go
    opt: paths=source_relative
  - remote: buf.build/protocolbuffers/go
    out: gen/go
    opt: paths=source_relative
  # TypeScript frontend
  - remote: buf.build/bufbuild/es
    out: gen/ts
    opt: target=ts
  - remote: buf.build/connectrpc/es
    out: gen/ts
    opt: target=ts
  # Python backend
  - remote: buf.build/protocolbuffers/python
    out: gen/python
```

```bash
buf generate   # generates all targets
buf lint        # lint protos
buf breaking --against '.git#branch=main'  # check breaking changes
```

### 3. Backend Implementation

#### Go (Primary — see `references/go.md`)

```go
package main

import (
    "context"
    "net/http"
    "golang.org/x/net/http2"
    "golang.org/x/net/http2/h2c"
    "connectrpc.com/connect"
    userv1 "example/gen/go/myapp/v1"
    "example/gen/go/myapp/v1/myappv1connect"
)

type UserServer struct{}

func (s *UserServer) GetUser(
    ctx context.Context,
    req *connect.Request[userv1.GetUserRequest],
) (*connect.Response[userv1.GetUserResponse], error) {
    if req.Msg.Id == "" {
        return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Errorf("id required"))
    }
    return connect.NewResponse(&userv1.GetUserResponse{
        User: &userv1.User{Id: req.Msg.Id, Name: "Alice"},
    }), nil
}

func main() {
    mux := http.NewServeMux()
    path, handler := myappv1connect.NewUserServiceHandler(&UserServer{})
    mux.Handle(path, handler)
    http.ListenAndServe(":8080", h2c.NewHandler(mux, &http2.Server{}))
}
```

#### Python (Beta — see `references/python.md`)

```python
import connectrpc
from gen.myapp.v1 import user_pb2

class UserService:
    async def get_user(self, request, context):
        return user_pb2.GetUserResponse(
            user=user_pb2.User(id=request.id, name="Alice")
        )

# ASGI app
app = connectrpc.create_app(services=[UserService()])
# Run: uvicorn main:app
```

### 4. Frontend Implementation

#### TypeScript/React with connect-query (see `references/typescript.md`)

```typescript
import { createConnectTransport } from "@connectrpc/connect-web";
import { TransportProvider } from "@connectrpc/connect-query";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useQuery } from "@connectrpc/connect-query";
import { getUser } from "./gen/myapp/v1/user-UserService_connectquery";

const transport = createConnectTransport({ baseUrl: "http://localhost:8080" });
const queryClient = new QueryClient();

// Wrap app
<TransportProvider transport={transport}>
  <QueryClientProvider client={queryClient}>
    <App />
  </QueryClientProvider>
</TransportProvider>

// In component
function UserProfile({ id }: { id: string }) {
  const { data } = useQuery(getUser, { id });
  return <div>{data?.user?.name}</div>;
}
```

#### Angular (Manual DI — see `references/typescript.md`)

```typescript
// transport.service.ts
@Injectable({ providedIn: 'root' })
export class TransportService {
  readonly transport = createConnectTransport({
    baseUrl: environment.apiUrl,
  });
}

// user.service.ts
@Injectable({ providedIn: 'root' })
export class UserService {
  private client: PromiseClient<typeof UserServiceDef>;
  constructor(private transportService: TransportService) {
    this.client = createPromiseClient(UserServiceDef, this.transportService.transport);
  }
  getUser(id: string) {
    return from(this.client.getUser({ id }));
  }
}
```

---

## Key Patterns

### Error Handling
- Use `connect.CodeXxx` constants (Go) or `ConnectError` (TS) — maps to gRPC codes
- Common: `CodeNotFound`, `CodeInvalidArgument`, `CodeUnauthenticated`, `CodePermissionDenied`
- Attach details: `connect.NewError(code, err)` with `detail, _ := connect.NewErrorDetail(msg)`

### Interceptors (Middleware)
- Go: `connect.UnaryInterceptorFunc(func(next connect.UnaryFunc) connect.UnaryFunc { ... })`
- TS: `Interceptor` type — `(next) => async (req) => { /* before */ const res = await next(req); /* after */ return res; }`
- Python: similar interceptor chain pattern

### Streaming
- **Server streaming**: handler receives request, sends via `stream.Send()`
- **Client streaming**: handler reads via `stream.Receive()` in loop
- **Bidi streaming**: both send/receive concurrently
- Web browsers: only server streaming supported (via connect protocol, not gRPC-Web)

### Protocol Support
- Connect protocol (default): HTTP/1.1 + HTTP/2, JSON + Protobuf, works with curl
- gRPC protocol: full gRPC compatibility, requires HTTP/2
- gRPC-Web: browser-compatible, HTTP/1.1 OK
- Clients auto-negotiate; servers handle all three simultaneously

---

## Reference Docs

For detailed patterns, see:
- `references/go.md` — Go backend: handlers, interceptors, streaming, testing, project structure
- `references/typescript.md` — TypeScript: connect-es, connect-web, connect-query, Angular DI, React hooks
- `references/python.md` — Python backend: ASGI/WSGI, codegen, interceptors, OpenTelemetry
- `references/buf-tooling.md` — Buf CLI: lint rules, breaking changes, BSR, polyglot generation

---

## Quick Reference

| Package | Install | Purpose |
|---|---|---|
| `connectrpc.com/connect` | `go get` | Go server + client |
| `@connectrpc/connect` | `npm i` | TS/JS core |
| `@connectrpc/connect-web` | `npm i` | Browser transport |
| `@connectrpc/connect-query` | `npm i` | TanStack Query integration |
| `@bufbuild/protobuf` | `npm i` | TS protobuf runtime |
| `connectrpc` | `pip install` | Python (>=3.10, beta) |
| `buf` | `brew install bufbuild/buf/buf` | Proto toolchain |

## Common Commands

```bash
buf generate                              # generate all code
buf lint                                  # lint protos
buf breaking --against '.git#branch=main' # check breaking changes
buf curl http://localhost:8080 --data '{"id":"1"}' --schema proto myapp.v1.UserService/GetUser  # test
```
