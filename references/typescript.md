# ConnectRPC TypeScript Frontend Reference

## Defaults

- Use **Connect-ES v2** patterns
- Use `createClient()` from `@connectrpc/connect` — **not** `createPromiseClient()`
- Import services from generated `*_pb` files — **not** `*_connect`
- Use `createConnectTransport()` as the default browser transport
- Add Connect-Query only when you actually want TanStack Query integration
- Create the transport once and reuse it across the app

## Packages

| Package | Purpose |
|---|---|
| `@connectrpc/connect` | Core client, errors, interceptors |
| `@connectrpc/connect-web` | Browser transports for Connect and gRPC-Web |
| `@connectrpc/connect-node` | Node.js transports for Connect, gRPC, and gRPC-Web |
| `@connectrpc/connect-query` | TanStack Query runtime integration |
| `@bufbuild/protobuf` | Protobuf-ES runtime |
| `@bufbuild/protoc-gen-es` | Generates `*_pb.ts` files |
| `@connectrpc/protoc-gen-connect-query` | Optional plugin for `*_connectquery.ts` helpers |
|

## Code Generation

### Core Connect-ES v2 generation

Use Buf v2 with `buf.build/bufbuild/es`. This generates messages **and** service definitions into `*_pb.ts`.

```yaml
# buf.gen.yaml
version: v2
plugins:
  - remote: buf.build/bufbuild/es
    out: src/gen
    opt: target=ts
```

Generated output looks like:

```text
src/gen/
  user_pb.ts
```

The service definition is imported from the same generated file:

```typescript
import { UserService } from "./gen/user_pb";
```

### Optional Connect-Query generation

If you use TanStack Query, add the query generator as a **local** plugin:

```yaml
# buf.gen.yaml
version: v2
plugins:
  - remote: buf.build/bufbuild/es
    out: src/gen
    opt: target=ts
  - local: protoc-gen-connect-query
    out: src/gen
    opt: target=ts
```

Install the plugin and runtime:

```bash
npm install --save-dev @bufbuild/protoc-gen-es @connectrpc/protoc-gen-connect-query
npm install @connectrpc/connect-query @tanstack/react-query @bufbuild/protobuf
```

Generated output then includes method helpers like:

```text
src/gen/
  user_pb.ts
  user-UserService_connectquery.ts
```

## Browser Client (default)

```typescript
import { createClient } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";
import { UserService } from "./gen/user_pb";

const transport = createConnectTransport({
  baseUrl: "https://api.example.com",
  defaultTimeoutMs: 5000,
  // useBinaryFormat: true, // opt in later if you need smaller payloads
  // useHttpGet: true,      // only for side-effect-free unary RPCs
});

const client = createClient(UserService, transport);

const response = await client.getUser(
  { id: "123" },
  {
    headers: { authorization: "Bearer token" },
  },
);

console.log(response.user?.name);
```

### When to use gRPC-Web

Use `createGrpcWebTransport()` only when the backend does **not** support the Connect protocol and you must talk to an existing gRPC-Web endpoint.

```typescript
import { createClient } from "@connectrpc/connect";
import { createGrpcWebTransport } from "@connectrpc/connect-web";
import { UserService } from "./gen/user_pb";

const transport = createGrpcWebTransport({
  baseUrl: "https://grpc-web.example.com",
});

const client = createClient(UserService, transport);
```

## React with Connect-Query

### App setup

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { TransportProvider } from "@connectrpc/connect-query";
import { createConnectTransport } from "@connectrpc/connect-web";

const queryClient = new QueryClient();
const transport = createConnectTransport({ baseUrl: "/api" });

root.render(
  <TransportProvider transport={transport}>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </TransportProvider>
);
```

### Unary query

```tsx
import { useQuery } from "@connectrpc/connect-query";
import { getUser } from "./gen/user-UserService_connectquery";

function UserProfile({ id }: { id: string }) {
  const { data, isLoading, error } = useQuery(getUser, { id });

  if (isLoading) return <Spinner />;
  if (error) return <ErrorView error={error} />;
  return <div>{data?.user?.name}</div>;
}
```

### Mutation

```tsx
import { useMutation } from "@connectrpc/connect-query";
import { createUser } from "./gen/user-UserService_connectquery";

function CreateUserForm() {
  const mutation = useMutation(createUser);

  const onSubmit = (name: string) => {
    mutation.mutate({ name });
  };

  return <form onSubmit={...}>...</form>;
}
```

## Angular Integration (manual DI)

There is no official Angular adapter. Use Angular DI for a singleton transport and client.

### Transport service

```typescript
import { Injectable } from "@angular/core";
import { createConnectTransport } from "@connectrpc/connect-web";
import type { Interceptor } from "@connectrpc/connect";
import { environment } from "../environments/environment";

const authInterceptor: Interceptor = (next) => async (req) => {
  const token = localStorage.getItem("token");
  if (token) {
    req.header.set("Authorization", `Bearer ${token}`);
  }
  return next(req);
};

@Injectable({ providedIn: "root" })
export class TransportService {
  readonly transport = createConnectTransport({
    baseUrl: environment.apiUrl,
    interceptors: [authInterceptor],
  });
}
```

### RPC service

```typescript
import { Injectable } from "@angular/core";
import { createClient, type Client } from "@connectrpc/connect";
import { from, type Observable } from "rxjs";
import { UserService, type GetUserResponse, type ListUsersResponse } from "../gen/user_pb";
import { TransportService } from "./transport.service";

@Injectable({ providedIn: "root" })
export class UserRpcService {
  private readonly client: Client<typeof UserService>;

  constructor(transportService: TransportService) {
    this.client = createClient(UserService, transportService.transport);
  }

  getUser(id: string): Observable<GetUserResponse> {
    return from(this.client.getUser({ id }));
  }

  listUsers(pageToken?: string): Observable<ListUsersResponse> {
    return from(this.client.listUsers({ pageToken, pageSize: 20 }));
  }
}
```

## Interceptors and Error Handling

```typescript
import { ConnectError, Code, type Interceptor } from "@connectrpc/connect";

const loggingInterceptor: Interceptor = (next) => async (req) => {
  const start = performance.now();
  try {
    const res = await next(req);
    console.log(`${req.method.name}: ${(performance.now() - start).toFixed(0)}ms`);
    return res;
  } catch (err) {
    console.error(`${req.method.name} failed`, err);
    throw err;
  }
};

try {
  await client.getUser({ id: "123" });
} catch (err) {
  if (err instanceof ConnectError) {
    switch (err.code) {
      case Code.NotFound:
        console.log("User not found");
        break;
      case Code.Unauthenticated:
        redirectToLogin();
        break;
      case Code.InvalidArgument:
        showValidationError(err.message);
        break;
      default:
        showGenericError(err.message);
    }
  }
}
```

## Streaming and Protocol Gotchas

- Browsers can reliably do **server streaming**. Do not assume client or bidi streaming in browser UIs.
- Use the Connect protocol by default. Reach for gRPC-Web only for compatibility with existing infrastructure.
- Keep the transport singleton-scoped. Creating a new transport per render is wasteful and complicates caching/interceptors.
- Prefer JSON format while debugging in the browser. Add `useBinaryFormat: true` later if payload size matters.

## Avoid These Stale Patterns

- `createPromiseClient()` → replaced by `createClient()`
- `import { UserService } from "./user_connect"` → import from `./user_pb`
- `buf.build/connectrpc/es` in `buf.gen.yaml` → remove it for Connect-ES v2
- Treating Connect-Query as mandatory → it is optional and only needed with TanStack Query
