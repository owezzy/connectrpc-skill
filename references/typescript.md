# ConnectRPC TypeScript Browser Reference

## Defaults

- Use **Connect-ES v2** patterns
- Use `createClient()` from `@connectrpc/connect` — **not** `createPromiseClient()`
- Import services from generated `*_pb` files — **not** `*_connect`
- Use `createConnectTransport()` as the default browser transport
- Add Connect-Query only when you actually want TanStack Query integration
- Create the transport once and reuse it across the app
- Treat **server streaming** as the reliable browser streaming case
- Use `create()` and `ConnectError.from()` when you need typed test requests or defensive error handling

## Packages

| Package | Purpose |
|---|---|
| `@connectrpc/connect` | Core client, errors, interceptors |
| `@connectrpc/connect-web` | Browser transports for Connect and gRPC-Web |
| `@connectrpc/connect-node` | Node.js transports for Connect, gRPC, and gRPC-Web |
| `@connectrpc/connect-query` | TanStack Query runtime integration |
| `@bufbuild/protobuf` | Protobuf-ES runtime and `create()` helper |
| `@bufbuild/protoc-gen-es` | Generates `*_pb.ts` files |
| `@connectrpc/protoc-gen-connect-query` | Optional plugin for `*_connectquery.ts` helpers |

## Code Generation

### Core Connect-ES v2 generation

Use Buf v2 with a local `protoc-gen-es` plugin. This matches the official examples and removes stale generated files with `clean: true`.

```yaml
# buf.gen.yaml
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

### Message creation in tests or wrappers

The official examples use `create()` when they need an explicit message instance instead of a plain object literal.

```typescript
import { create } from "@bufbuild/protobuf";
import { IntroduceRequestSchema } from "./gen/user_pb";

const request = create(IntroduceRequestSchema, {
  name: "Jane",
});
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

### Headers and trailers

Pass request metadata with `headers`, and remember that browser clients can only read response trailers if the server exposes the right CORS headers.

```typescript
const response = await client.getUser(
  { id: "123" },
  {
    headers: {
      authorization: "Bearer token",
      "x-request-id": crypto.randomUUID(),
    },
    onHeader(headers) {
      console.log("response headers", headers);
    },
    onTrailer(trailers) {
      console.log("response trailers", trailers);
    },
  },
);
```

If trailers are unexpectedly empty in the browser, check the server CORS configuration before changing client code.

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
  </TransportProvider>,
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

## Angular Integration

There is no official Angular adapter. Follow the official Angular example pattern instead of wrapping `createClient()` calls with `from(...)` one method at a time.

### Provider-backed transport

```typescript
import { inject, InjectionToken, type Provider } from "@angular/core";
import type { DescService } from "@bufbuild/protobuf";
import type { Interceptor, Transport } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";
import { createObservableClient, type ObservableClient } from "./observable-client";

const TRANSPORT = new InjectionToken<Transport>("connect.transport");

export const INTERCEPTORS = new InjectionToken<Interceptor[]>("connect.interceptors", {
  factory: () => [],
});

export function createClientToken<T extends DescService>(service: T) {
  return new InjectionToken<ObservableClient<T>>(`client for ${service.typeName}`, {
    factory() {
      return createObservableClient(service, inject(TRANSPORT));
    },
  });
}

export function provideConnect(
  options: Omit<Parameters<typeof createConnectTransport>[0], "interceptors">,
): Provider[] {
  return [
    {
      provide: TRANSPORT,
      useFactory: (interceptors: Interceptor[]) =>
        createConnectTransport({
          ...options,
          interceptors,
        }),
      deps: [INTERCEPTORS],
    },
  ];
}
```

### Observable client wrapper

```typescript
import { makeAnyClient, type CallOptions, type Transport } from "@connectrpc/connect";
import { createAsyncIterable } from "@connectrpc/connect/protocol";
import {
  type DescMessage,
  type DescMethodServerStreaming,
  type DescMethodStreaming,
  type DescMethodUnary,
  type DescService,
  type MessageInitShape,
  type MessageShape,
} from "@bufbuild/protobuf";
import { Observable } from "rxjs";

export type ObservableClient<T extends DescService> = {
  [P in keyof T["method"]]: T["method"][P] extends DescMethodUnary<infer I, infer O>
    ? (request: MessageInitShape<I>, options?: CallOptions) => Observable<MessageShape<O>>
    : T["method"][P] extends DescMethodServerStreaming<infer I, infer O>
      ? (request: MessageInitShape<I>, options?: CallOptions) => Observable<MessageShape<O>>
      : never;
};

export function createObservableClient<T extends DescService>(service: T, transport: Transport) {
  return makeAnyClient(service, (method: DescMethodUnary | DescMethodStreaming) => {
    switch (method.methodKind) {
      case "unary":
        return (requestMessage, options) =>
          new Observable((subscriber) => {
            transport
              .unary(method, options?.signal, options?.timeoutMs, options?.headers, requestMessage)
              .then(
                (response) => {
                  options?.onHeader?.(response.header);
                  subscriber.next(response.message);
                  options?.onTrailer?.(response.trailer);
                },
                (err) => subscriber.error(err),
              )
              .finally(() => subscriber.complete());
          });
      case "server_streaming":
        return (requestMessage, options) =>
          new Observable((subscriber) => {
            transport
              .stream(
                method as DescMethodServerStreaming<DescMessage, DescMessage>,
                options?.signal,
                options?.timeoutMs,
                options?.headers,
                createAsyncIterable([requestMessage]),
              )
              .then(
                async (response) => {
                  options?.onHeader?.(response.header);
                  for await (const item of response.message) {
                    subscriber.next(item);
                  }
                  options?.onTrailer?.(response.trailer);
                },
                (err) => subscriber.error(err),
              )
              .finally(() => subscriber.complete());
          });
      default:
        return null;
    }
  }) as ObservableClient<T>;
}
```

This pattern matters because it keeps Angular DI, interceptors, unary RPCs, and server-streaming RPCs aligned with one transport instance.

### Using the token in a component

```typescript
import { Component, inject } from "@angular/core";
import { ELIZA } from "../connect/tokens";

@Component({
  selector: "app-root",
  template: `...`,
})
export class AppComponent {
  private readonly client = inject(ELIZA);

  send(sentence: string) {
    this.client.say({ sentence }).subscribe({
      next: (res) => console.log(res.sentence),
      error: (err) => console.error(err),
    });
  }
}
```

## Interceptors and Error Handling

```typescript
import { Code, ConnectError, type Interceptor } from "@connectrpc/connect";

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
  const connectErr = ConnectError.from(err);
  switch (connectErr.code) {
    case Code.NotFound:
      console.log("User not found");
      break;
    case Code.Unauthenticated:
      redirectToLogin();
      break;
    case Code.InvalidArgument:
      showValidationError(connectErr.message);
      break;
    default:
      showGenericError(connectErr.message);
  }
}
```

Use `ConnectError.from(err)` when the error may come from browser fetch behavior, wrappers, or general promise chains.

## Streaming and Protocol Gotchas

- Browsers can reliably do **server streaming**. Do not assume client or bidi streaming in browser UIs unless you have explicitly verified runtime support outside the browser.
- Use the Connect protocol by default. Reach for gRPC-Web only for compatibility with existing infrastructure.
- Keep the transport singleton-scoped. Creating a new transport per render is wasteful and complicates caching, headers, and interceptor behavior.
- Prefer JSON format while debugging in the browser. Add `useBinaryFormat: true` later if payload size matters.

### Transport anti-pattern

Avoid creating a transport inside a component render path or hook body:

```typescript
function BadExample() {
  const client = createClient(
    UserService,
    createConnectTransport({ baseUrl: "/api" }),
  );

  return <button onClick={() => client.getUser({ id: "123" })}>Load</button>;
}
```

This recreates interceptors and transport state on every render. Build the transport once at app startup or DI-provider scope.

## CORS Reminder

When browser clients need trailers or custom headers, the server must expose the Connect CORS headers. If browser calls work in Node tests but fail in the browser, check the server middleware before changing the client.

## Avoid These Stale Patterns

- `createPromiseClient()` → replaced by `createClient()`
- `import { UserService } from "./user_connect"` → import from `./user_pb`
- `buf.build/connectrpc/es` in `buf.gen.yaml` → remove it for Connect-ES v2
- `from(client.method())` as the main Angular integration strategy → use provider-backed transport + `ObservableClient<T>`
- Treating Connect-Query as mandatory → it is optional and only needed with TanStack Query
