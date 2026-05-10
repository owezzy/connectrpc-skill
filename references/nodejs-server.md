# ConnectRPC Node.js Server Reference

## Defaults

- Use **Connect protocol** first, then fall back to gRPC-Web only for compatibility
- Define handlers with `ConnectRouter` and `router.service()`
- Use framework adapters instead of hand-rolling protocol details
- Treat CORS as HTTP middleware configuration, not interceptor work
- Test server code with the official **three-tier model**: in-memory transport, full HTTP server, direct handler unit tests

## Packages

| Package | Purpose |
|---|---|
| `@connectrpc/connect` | Router types, errors, interceptors, CORS constants, in-memory testing transport |
| `@connectrpc/connect-node` | Node transports and the vanilla Node adapter |
| `@connectrpc/connect-express` | Express middleware |
| `@bufbuild/protobuf` | Message creation helpers such as `create()` |

## Route Definitions

Define routes with `ConnectRouter` and register all RPC shapes in one place.

```typescript
import { ConnectRouter } from "@connectrpc/connect";
import { ElizaService } from "./gen/connectrpc/eliza/v1/eliza_pb.js";
import type {
  ConverseRequest,
  IntroduceRequest,
  SayRequest,
} from "./gen/connectrpc/eliza/v1/eliza_pb.js";

export default (router: ConnectRouter) =>
  router.service(ElizaService, {
    say(req: SayRequest) {
      return { sentence: `You said ${req.sentence}` };
    },

    async *introduce(req: IntroduceRequest) {
      yield { sentence: `Hi ${req.name}, I'm Eliza` };
      yield { sentence: `How are you feeling today?` };
    },

    async *converse(reqs: AsyncIterable<ConverseRequest>) {
      for await (const req of reqs) {
        yield { sentence: `You said ${req.sentence}` };
      }
    },
  });
```

### Handler shape reminders

- **Unary** → regular function returning a message object
- **Server streaming** → `async *method(req)`
- **Bidi streaming** → `async *method(reqs: AsyncIterable<Req>)`

## Vanilla Node HTTP

Use `connectNodeAdapter()` when you are serving ConnectRPC routes from the built-in `http` module.

```typescript
import http from "node:http";
import { cors as connectCors } from "@connectrpc/connect";
import { connectNodeAdapter } from "@connectrpc/connect-node";
import cors from "cors";
import routes from "./connect.js";

const handler = connectNodeAdapter({
  routes,
});

const corsHandler = cors({
  origin: true,
  methods: [...connectCors.allowedMethods],
  allowedHeaders: [...connectCors.allowedHeaders],
  exposedHeaders: [...connectCors.exposedHeaders],
});

export function build() {
  return http.createServer((req, res) => {
    corsHandler(req, res, () => handler(req, res));
  });
}
```

### Fallback handlers

`connectNodeAdapter()` also accepts `fallback(req, res)` for non-RPC routes. Use it when you need one Node server to serve both Connect endpoints and regular HTTP content.

## Express

Use `expressConnectMiddleware()` instead of manually dispatching request paths.

```typescript
import express from "express";
import cors from "cors";
import http from "node:http";
import { cors as connectCors } from "@connectrpc/connect";
import { expressConnectMiddleware } from "@connectrpc/connect-express";
import routes from "./connect.js";

export function build() {
  const app = express();

  app.use(
    cors({
      origin: true,
      methods: [...connectCors.allowedMethods],
      allowedHeaders: [...connectCors.allowedHeaders],
      exposedHeaders: [...connectCors.exposedHeaders],
    }),
  );

  app.use(
    expressConnectMiddleware({
      routes,
    }),
  );

  return http.createServer(app);
}
```

## Client and Integration Testing

### Tier 1: in-memory server

Use `createRouterTransport(routes)` when you want real handlers without a real HTTP server.

```typescript
import { createClient, createRouterTransport } from "@connectrpc/connect";
import { ElizaService } from "./gen/connectrpc/eliza/v1/eliza_pb.js";
import routes from "./connect.js";

const transport = createRouterTransport(routes);
const client = createClient(ElizaService, transport);

const response = await client.say({ sentence: "hello" });
```

### Tier 2: mocked RPC methods

Use the `rpc()` builder form to isolate one method in client tests.

```typescript
import { createRouterTransport, type MethodImpl } from "@connectrpc/connect";
import { ElizaService } from "./gen/connectrpc/eliza/v1/eliza_pb.js";

const introduce: MethodImpl<typeof ElizaService.method.introduce> = async function* () {
  yield { sentence: "Hi Joe, I'm Eliza" };
};

const transport = createRouterTransport(({ rpc }) => {
  rpc(ElizaService.method.introduce, introduce);
});
```

### Tier 3: full HTTP server

Use a helper that starts the server on port `0` so the OS assigns a free port.

```typescript
import { afterEach, beforeEach } from "node:test";
import { createConnectTransport } from "@connectrpc/connect-node";
import type { Server } from "node:http";

export function setupTestServer(createServer: () => Server) {
  let server: Server | undefined;

  beforeEach((_ctx, done) => {
    server = createServer().listen(0, done);
  });

  afterEach(() => server?.close());

  return () => {
    const address = server?.address();
    if (!address || typeof address === "string") {
      throw new Error("cannot determine server address");
    }
    return createConnectTransport({
      baseUrl: `http://localhost:${address.port}`,
      httpVersion: "1.1",
    });
  };
}
```

## Direct Handler Unit Tests

When you want pure unit tests with injected dependencies, implement the service as a class with `ServiceImpl<typeof Service>`.

```typescript
import { create } from "@bufbuild/protobuf";
import type { ServiceImpl } from "@connectrpc/connect";
import { ElizaService, SayRequestSchema, type SayRequest } from "./gen/connectrpc/eliza/v1/eliza_pb.js";

class Eliza implements ServiceImpl<typeof ElizaService> {
  say(req: SayRequest) {
    return { sentence: `You said ${req.sentence}` };
  }
}

const service = new Eliza();
const response = await service.say(create(SayRequestSchema, { sentence: "hello" }));
```

Prefer this style when the handler depends on repositories, clocks, feature flags, or other injected collaborators.

## Errors and Message Creation

Use `create()` when you need a typed request in tests.

```typescript
import { create } from "@bufbuild/protobuf";
import { SayRequestSchema } from "./gen/connectrpc/eliza/v1/eliza_pb.js";

const request = create(SayRequestSchema, { sentence: "hello" });
```

Use `ConnectError.from()` in catch blocks when the thrown value may not already be a `ConnectError`.

```typescript
import { Code, ConnectError } from "@connectrpc/connect";

try {
  await client.say({ sentence: "hello" });
} catch (err) {
  switch (ConnectError.from(err).code) {
    case Code.Unavailable:
      console.log("service unavailable");
      break;
    default:
      console.log("unexpected failure");
  }
}
```

## Context Values

When you need per-request dependencies, follow the context key lifecycle shown in the official Cloudflare Workers example.

```typescript
import { createContextKey, type HandlerContext } from "@connectrpc/connect";

export const kStore = createContextKey<KVNamespace | undefined>(undefined);

function getStore(ctx: HandlerContext): KVNamespace {
  const store = ctx.values.get(kStore);
  if (!store) {
    throw new Error("store missing from request context");
  }
  return store;
}
```

Set these values at the adapter or request-boundary layer, not inside handlers.

## Keep / Avoid

Keep:

- `ConnectRouter` route definitions in one module
- `createRouterTransport()` for fast tests
- `connectCors` constants for CORS config
- `ConnectError.from(err)` in broad catch blocks

Avoid:

- manually dispatching Connect protocol paths
- building browser-facing CORS rules by hand when the constants already exist
- replacing in-memory tests with full HTTP servers for every test
- burying request-scoped dependencies in globals when context values fit better
