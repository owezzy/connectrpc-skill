# ConnectRPC Go Backend Reference

## Project Structure

```
myservice/
├── buf.gen.yaml
├── buf.yaml
├── cmd/
│   └── server/
│       └── main.go
├── gen/                    # generated code (git-ignored or committed)
│   └── myapp/v1/
│       ├── user.pb.go
│       └── myappv1connect/
│           └── user.connect.go
├── internal/
│   ├── server/             # handler implementations
│   │   └── user.go
│   └── interceptor/        # custom interceptors
│       ├── auth.go
│       └── logging.go
├── proto/
│   └── myapp/v1/
│       └── user.proto
├── go.mod
└── go.sum
```

## Handler Implementation

### Simple Mode (default, recommended)

```go
// internal/server/user.go
type UserServer struct{}

// Each RPC method gets: (ctx, *connect.Request[ReqType]) (*connect.Response[ResType], error)
func (s *UserServer) GetUser(
    ctx context.Context,
    req *connect.Request[userv1.GetUserRequest],
) (*connect.Response[userv1.GetUserResponse], error) {
    // Access headers
    authHeader := req.Header().Get("Authorization")

    // Access message
    userID := req.Msg.Id

    // Return with response headers
    res := connect.NewResponse(&userv1.GetUserResponse{
        User: &userv1.User{Id: userID, Name: "Alice"},
    })
    res.Header().Set("X-Custom-Header", "value")
    return res, nil
}
```

### Server Streaming

```go
func (s *UserServer) ListUsers(
    ctx context.Context,
    req *connect.Request[userv1.ListUsersRequest],
    stream *connect.ServerStream[userv1.ListUsersResponse],
) error {
    for _, user := range users {
        if err := stream.Send(&userv1.ListUsersResponse{User: user}); err != nil {
            return err
        }
    }
    return nil
}
```

### Client Streaming

```go
func (s *UserServer) CreateUsers(
    ctx context.Context,
    stream *connect.ClientStream[userv1.CreateUserRequest],
) (*connect.Response[userv1.CreateUsersResponse], error) {
    var count int32
    for stream.Receive() {
        msg := stream.Msg()
        // process msg
        count++
    }
    if err := stream.Err(); err != nil {
        return nil, err
    }
    return connect.NewResponse(&userv1.CreateUsersResponse{Count: count}), nil
}
```

### Bidi Streaming

```go
func (s *UserServer) Chat(
    ctx context.Context,
    stream *connect.BidiStream[userv1.ChatRequest, userv1.ChatResponse],
) error {
    for {
        msg, err := stream.Receive()
        if errors.Is(err, io.EOF) {
            return nil
        }
        if err != nil {
            return err
        }
        if err := stream.Send(&userv1.ChatResponse{Text: "echo: " + msg.Text}); err != nil {
            return err
        }
    }
}
```

## Error Handling

```go
import "connectrpc.com/connect"

// Basic error
return nil, connect.NewError(connect.CodeNotFound, fmt.Errorf("user %s not found", id))

// Error with details (attach protobuf messages)
detail, err := connect.NewErrorDetail(&errdetails.ErrorInfo{
    Reason: "USER_NOT_FOUND",
    Domain: "myapp.v1",
    Metadata: map[string]string{"user_id": id},
})
if err != nil {
    return nil, err
}
connErr := connect.NewError(connect.CodeNotFound, fmt.Errorf("user not found"))
connErr.AddDetail(detail)
return nil, connErr

// Common codes
connect.CodeInvalidArgument  // 400 - bad input
connect.CodeNotFound         // 404 - resource missing
connect.CodeAlreadyExists    // 409 - duplicate
connect.CodeUnauthenticated  // 401 - no/bad credentials
connect.CodePermissionDenied // 403 - insufficient permissions
connect.CodeInternal         // 500 - server bug
connect.CodeUnavailable      // 503 - transient failure
```

## Interceptors

```go
// Unary interceptor
func NewAuthInterceptor(tokenValidator TokenValidator) connect.UnaryInterceptorFunc {
    return connect.UnaryInterceptorFunc(func(next connect.UnaryFunc) connect.UnaryFunc {
        return connect.UnaryFunc(func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
            // Skip for health checks
            if req.Spec().Procedure == "/grpc.health.v1.Health/Check" {
                return next(ctx, req)
            }
            // Only intercept requests (not responses in client interceptors)
            if req.Spec().IsClient {
                return next(ctx, req)
            }
            token := req.Header().Get("Authorization")
            claims, err := tokenValidator.Validate(strings.TrimPrefix(token, "Bearer "))
            if err != nil {
                return nil, connect.NewError(connect.CodeUnauthenticated, err)
            }
            ctx = context.WithValue(ctx, claimsKey{}, claims)
            return next(ctx, req)
        })
    })
}

// Logging interceptor
func NewLoggingInterceptor(logger *slog.Logger) connect.UnaryInterceptorFunc {
    return connect.UnaryInterceptorFunc(func(next connect.UnaryFunc) connect.UnaryFunc {
        return connect.UnaryFunc(func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
            start := time.Now()
            res, err := next(ctx, req)
            logger.Info("rpc",
                "procedure", req.Spec().Procedure,
                "duration", time.Since(start),
                "error", err,
            )
            return res, err
        })
    })
}

// Apply interceptors
path, handler := myappv1connect.NewUserServiceHandler(
    &UserServer{},
    connect.WithInterceptors(
        NewLoggingInterceptor(logger),
        NewAuthInterceptor(validator),
    ),
)
```

## Server Setup

```go
func main() {
    mux := http.NewServeMux()

    // Register services
    userPath, userHandler := myappv1connect.NewUserServiceHandler(&UserServer{},
        connect.WithInterceptors(interceptors...),
    )
    mux.Handle(userPath, userHandler)

    // Health check (optional)
    healthPath, healthHandler := grpchealth.NewHandler(grpchealth.NewStaticChecker(
        myappv1connect.UserServiceName,
    ))
    mux.Handle(healthPath, healthHandler)

    // Reflection (optional, for grpcurl/buf curl)
    reflectPath, reflectHandler := grpcreflect.NewHandlerV1Alpha(
        grpcreflect.NewStaticReflector(myappv1connect.UserServiceName),
    )
    mux.Handle(reflectPath, reflectHandler)

    // CORS for browser clients
    corsHandler := cors.New(cors.Options{
        AllowedOrigins: []string{"http://localhost:3000"},
        AllowedMethods: connectcors.AllowedMethods(),
        AllowedHeaders: connectcors.AllowedHeaders(),
        ExposedHeaders: connectcors.ExposedHeaders(),
    }).Handler(mux)

    // h2c for HTTP/2 without TLS (dev)
    server := &http.Server{
        Addr:    ":8080",
        Handler: h2c.NewHandler(corsHandler, &http2.Server{}),
    }
    server.ListenAndServe()
}
```

## Go Client

```go
client := myappv1connect.NewUserServiceClient(
    http.DefaultClient,
    "http://localhost:8080",
    connect.WithInterceptors(clientInterceptors...),
)

res, err := client.GetUser(ctx, connect.NewRequest(&userv1.GetUserRequest{Id: "123"}))
if err != nil {
    var connectErr *connect.Error
    if errors.As(err, &connectErr) {
        fmt.Println(connectErr.Code(), connectErr.Message())
    }
    return err
}
fmt.Println(res.Msg.User.Name)
```

## Testing

```go
func TestGetUser(t *testing.T) {
    mux := http.NewServeMux()
    path, handler := myappv1connect.NewUserServiceHandler(&UserServer{})
    mux.Handle(path, handler)
    srv := httptest.NewUnstartedServer(mux)
    srv.EnableHTTP2 = true
    srv.StartTLS()
    defer srv.Close()

    client := myappv1connect.NewUserServiceClient(srv.Client(), srv.URL)
    res, err := client.GetUser(context.Background(),
        connect.NewRequest(&userv1.GetUserRequest{Id: "123"}))
    require.NoError(t, err)
    assert.Equal(t, "Alice", res.Msg.User.Name)
}
```

## Key Dependencies

```
go get connectrpc.com/connect
go get connectrpc.com/grpchealth       # health checks
go get connectrpc.com/grpcreflect      # reflection
go get connectrpc.com/cors             # CORS helpers
go get golang.org/x/net/http2          # h2c support
go get connectrpc.com/otelconnect      # OpenTelemetry
go get connectrpc.com/validate         # protovalidate integration
```
