# ConnectRPC TypeScript Frontend Reference

## Packages

| Package | Purpose |
|---|---|
| `@connectrpc/connect` | Core: client creation, interceptors, errors |
| `@connectrpc/connect-web` | Browser transports (Connect + gRPC-Web) |
| `@connectrpc/connect-node` | Node.js transports (Connect + gRPC + gRPC-Web) |
| `@connectrpc/connect-query` | TanStack Query integration (React) |
| `@bufbuild/protobuf` | Protobuf-ES runtime (required) |
| `@bufbuild/protoc-gen-es` | Protobuf codegen plugin |
| `@connectrpc/protoc-gen-connect-es` | Connect service codegen plugin |

## Transport Setup

```typescript
import { createConnectTransport, createGrpcWebTransport } from "@connectrpc/connect-web";

// Connect protocol (recommended for new projects)
const transport = createConnectTransport({
  baseUrl: "http://localhost:8080",
  // Optional: interceptors, credentials, JSON format
});

// gRPC-Web protocol (for existing gRPC backends)
const grpcTransport = createGrpcWebTransport({
  baseUrl: "http://localhost:8080",
});
```

## Client Creation

```typescript
import { createPromiseClient, createCallbackClient } from "@connectrpc/connect";
import { UserService } from "./gen/myapp/v1/user_connect";

// Promise-based (most common)
const client = createPromiseClient(UserService, transport);
const res = await client.getUser({ id: "123" });
console.log(res.user?.name);

// With headers
const res = await client.getUser(
  { id: "123" },
  { headers: new Headers({ Authorization: "Bearer token" }) },
);
```

## React + connect-query (TanStack Query)

### Setup

```tsx
// main.tsx
import { TransportProvider } from "@connectrpc/connect-query";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

const transport = createConnectTransport({ baseUrl: "/api" });
const queryClient = new QueryClient();

root.render(
  <TransportProvider transport={transport}>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </TransportProvider>
);
```

### Queries

```tsx
import { useQuery } from "@connectrpc/connect-query";
import { getUser } from "./gen/myapp/v1/user-UserService_connectquery";

function UserProfile({ id }: { id: string }) {
  const { data, isLoading, error } = useQuery(getUser, { id });

  if (isLoading) return <Spinner />;
  if (error) return <Error error={error} />;
  return <div>{data?.user?.name}</div>;
}
```

### Mutations

```tsx
import { useMutation } from "@connectrpc/connect-query";
import { createUser } from "./gen/myapp/v1/user-UserService_connectquery";

function CreateUserForm() {
  const mutation = useMutation(createUser);

  const handleSubmit = (name: string) => {
    mutation.mutate({ name }, {
      onSuccess: (data) => console.log("Created:", data.user?.id),
    });
  };

  return <form onSubmit={...}>...</form>;
}
```

### Infinite Queries (pagination)

```tsx
import { useInfiniteQuery } from "@connectrpc/connect-query";
import { listUsers } from "./gen/myapp/v1/user-UserService_connectquery";

function UserList() {
  const { data, fetchNextPage, hasNextPage } = useInfiniteQuery(
    listUsers,
    { pageSize: 20 },
    {
      pageParamKey: "pageToken",
      getNextPageParam: (lastPage) => lastPage.nextPageToken || undefined,
    }
  );
  // ...
}
```

## Angular Integration (Manual DI)

No official Angular adapter exists. Use manual dependency injection:

### Transport Service

```typescript
// services/transport.service.ts
import { Injectable } from '@angular/core';
import { createConnectTransport } from '@connectrpc/connect-web';
import { environment } from '../environments/environment';

@Injectable({ providedIn: 'root' })
export class TransportService {
  readonly transport = createConnectTransport({
    baseUrl: environment.apiUrl,
    interceptors: [authInterceptor],  // optional
  });
}
```

### RPC Service

```typescript
// services/user.service.ts
import { Injectable } from '@angular/core';
import { createPromiseClient, PromiseClient } from '@connectrpc/connect';
import { UserService as UserServiceDef } from '../gen/myapp/v1/user_connect';
import { TransportService } from './transport.service';
import { from, Observable } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class UserService {
  private client: PromiseClient<typeof UserServiceDef>;

  constructor(private transportService: TransportService) {
    this.client = createPromiseClient(UserServiceDef, this.transportService.transport);
  }

  getUser(id: string): Observable<GetUserResponse> {
    return from(this.client.getUser({ id }));
  }

  listUsers(pageToken?: string): Observable<ListUsersResponse> {
    return from(this.client.listUsers({ pageToken, pageSize: 20 }));
  }
}
```

### Component Usage

```typescript
// components/user-profile.component.ts
@Component({
  selector: 'app-user-profile',
  template: `
    @if (user$ | async; as user) {
      <h2>{{ user.user?.name }}</h2>
      <p>{{ user.user?.email }}</p>
    }
  `,
})
export class UserProfileComponent implements OnInit {
  user$!: Observable<GetUserResponse>;

  constructor(private userService: UserService) {}

  ngOnInit() {
    this.user$ = this.userService.getUser(this.userId);
  }
}
```

### Signal-based (Angular 16+)

```typescript
@Component({
  selector: 'app-user-profile',
  template: `
    @if (user()) {
      <h2>{{ user()!.user?.name }}</h2>
    }
  `,
})
export class UserProfileComponent {
  private userService = inject(UserService);
  userId = input.required<string>();
  user = toSignal(
    toObservable(this.userId).pipe(
      switchMap(id => this.userService.getUser(id))
    )
  );
}
```

## Interceptors (Client-side)

```typescript
import type { Interceptor } from "@connectrpc/connect";

// Auth interceptor
const authInterceptor: Interceptor = (next) => async (req) => {
  const token = getAuthToken();
  if (token) {
    req.header.set("Authorization", `Bearer ${token}`);
  }
  return next(req);
};

// Logging interceptor
const loggingInterceptor: Interceptor = (next) => async (req) => {
  const start = performance.now();
  try {
    const res = await next(req);
    console.log(`${req.method.name}: ${(performance.now() - start).toFixed(0)}ms`);
    return res;
  } catch (err) {
    console.error(`${req.method.name} failed:`, err);
    throw err;
  }
};

// Apply to transport
const transport = createConnectTransport({
  baseUrl: "/api",
  interceptors: [authInterceptor, loggingInterceptor],
});
```

## Error Handling

```typescript
import { ConnectError, Code } from "@connectrpc/connect";

try {
  const res = await client.getUser({ id: "123" });
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
    // Access error details
    for (const detail of err.details) {
      console.log(detail.type, detail.value);
    }
  }
}
```

## Server Streaming (Browser)

```typescript
// Only server streaming works in browsers (no client/bidi streaming)
for await (const res of client.listUsers({ pageSize: 10 })) {
  console.log(res.user);
}
```

## Node.js Server (connect-node)

```typescript
import { createConnectRouter } from "@connectrpc/connect";
import { connectNodeAdapter } from "@connectrpc/connect-node";
import { UserService } from "./gen/myapp/v1/user_connect";

const router = createConnectRouter().service(UserService, {
  async getUser(req) {
    return { user: { id: req.id, name: "Alice" } };
  },
});

// Express
app.use(connectNodeAdapter({ routes: router }));

// Fastify
await fastify.register(fastifyConnectPlugin, { routes: router });
```
