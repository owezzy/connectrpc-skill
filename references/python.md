# ConnectRPC Python Backend Reference

> **Status**: Beta (v0.10.0). Package renamed from `connect-python` to `connectrpc` in v0.9.0.
> **Requires**: Python >= 3.10

## Installation

```bash
pip install connectrpc
# Or with extras
pip install connectrpc[grpc]          # gRPC protocol support
pip install connectrpc[otel]          # OpenTelemetry tracing
pip install connectrpc[grpc,otel]     # both
```

## Code Generation

```yaml
# buf.gen.yaml
version: v2
plugins:
  - remote: buf.build/protocolbuffers/python
    out: gen/python
  # For gRPC stubs (optional)
  - remote: buf.build/grpc/python
    out: gen/python
```

```bash
buf generate
```

## ASGI Service (async, recommended)

```python
# server.py
import connectrpc
from gen.myapp.v1 import user_pb2, user_pb2_grpc

class UserServicer(user_pb2_grpc.UserServiceServicer):
    async def GetUser(self, request, context):
        if not request.id:
            raise connectrpc.ConnectError(
                code=connectrpc.Code.INVALID_ARGUMENT,
                message="id is required",
            )
        return user_pb2.GetUserResponse(
            user=user_pb2.User(id=request.id, name="Alice")
        )

    async def ListUsers(self, request, context):
        """Server streaming"""
        for user in get_users(page_size=request.page_size):
            yield user_pb2.ListUsersResponse(user=user)

# Create ASGI app
app = connectrpc.App(
    services=[UserServicer()],
    # Optional configuration
    interceptors=[logging_interceptor, auth_interceptor],
)

# Run with uvicorn
# uvicorn server:app --host 0.0.0.0 --port 8080
```

## WSGI Service (sync)

```python
import connectrpc

class UserServicer(user_pb2_grpc.UserServiceServicer):
    def GetUser(self, request, context):
        return user_pb2.GetUserResponse(
            user=user_pb2.User(id=request.id, name="Alice")
        )

# Create WSGI app
app = connectrpc.WSGIApp(services=[UserServicer()])

# Run with gunicorn
# gunicorn server:app --bind 0.0.0.0:8080
```

## Error Handling

```python
import connectrpc

# Raise errors with codes
raise connectrpc.ConnectError(
    code=connectrpc.Code.NOT_FOUND,
    message=f"User {request.id} not found",
)

raise connectrpc.ConnectError(
    code=connectrpc.Code.PERMISSION_DENIED,
    message="Insufficient permissions",
)

# With error details (protobuf messages)
from google.rpc import error_details_pb2

detail = error_details_pb2.ErrorInfo(
    reason="USER_NOT_FOUND",
    domain="myapp.v1",
    metadata={"user_id": request.id},
)
raise connectrpc.ConnectError(
    code=connectrpc.Code.NOT_FOUND,
    message="User not found",
    details=[detail],
)

# Available codes
connectrpc.Code.OK
connectrpc.Code.CANCELLED
connectrpc.Code.UNKNOWN
connectrpc.Code.INVALID_ARGUMENT
connectrpc.Code.NOT_FOUND
connectrpc.Code.ALREADY_EXISTS
connectrpc.Code.PERMISSION_DENIED
connectrpc.Code.UNAUTHENTICATED
connectrpc.Code.RESOURCE_EXHAUSTED
connectrpc.Code.FAILED_PRECONDITION
connectrpc.Code.UNIMPLEMENTED
connectrpc.Code.INTERNAL
connectrpc.Code.UNAVAILABLE
connectrpc.Code.DATA_LOSS
```

## Interceptors

```python
import connectrpc
from typing import Any, Callable

# Unary interceptor
async def auth_interceptor(
    request: Any,
    context: connectrpc.ServiceContext,
    handler: Callable,
) -> Any:
    token = context.request_headers.get("authorization", "")
    if not token.startswith("Bearer "):
        raise connectrpc.ConnectError(
            code=connectrpc.Code.UNAUTHENTICATED,
            message="Missing bearer token",
        )
    claims = validate_token(token.removeprefix("Bearer "))
    context.set("user_claims", claims)
    return await handler(request, context)

# Logging interceptor
async def logging_interceptor(
    request: Any,
    context: connectrpc.ServiceContext,
    handler: Callable,
) -> Any:
    import time
    start = time.monotonic()
    try:
        response = await handler(request, context)
        duration = time.monotonic() - start
        logger.info(f"{context.method}: {duration:.3f}s")
        return response
    except Exception as e:
        duration = time.monotonic() - start
        logger.error(f"{context.method}: {duration:.3f}s error={e}")
        raise

# Apply interceptors (order matters: first = outermost)
app = connectrpc.App(
    services=[UserServicer()],
    interceptors=[logging_interceptor, auth_interceptor],
)
```

## OpenTelemetry Integration

```python
pip install connectrpc[otel]

from connectrpc.otel import OtelInterceptor
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider

trace.set_tracer_provider(TracerProvider())

app = connectrpc.App(
    services=[UserServicer()],
    interceptors=[OtelInterceptor()],
)
```

## Python Client

```python
import connectrpc
from gen.myapp.v1 import user_pb2, user_pb2_grpc

# Create client
async with connectrpc.AsyncClient(
    base_url="http://localhost:8080",
) as client:
    stub = user_pb2_grpc.UserServiceStub(client)
    response = await stub.GetUser(user_pb2.GetUserRequest(id="123"))
    print(response.user.name)
```

## Framework Integration

### FastAPI Mount

```python
from fastapi import FastAPI
from connectrpc import App as ConnectApp

fastapi_app = FastAPI()
connect_app = ConnectApp(services=[UserServicer()])

# Mount ConnectRPC under /connect prefix
fastapi_app.mount("/connect", connect_app)

# Or mount at root (ConnectRPC handles its own routing)
fastapi_app.mount("/", connect_app)
```

### Starlette

```python
from starlette.applications import Starlette
from starlette.routing import Mount

app = Starlette(routes=[
    Mount("/", connect_app),
])
```

## Testing

```python
import pytest
from httpx import AsyncClient, ASGITransport

@pytest.fixture
def app():
    return connectrpc.App(services=[UserServicer()])

@pytest.mark.asyncio
async def test_get_user(app):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/myapp.v1.UserService/GetUser",
            json={"id": "123"},
            headers={"Content-Type": "application/json"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["user"]["name"] == "Alice"
```
