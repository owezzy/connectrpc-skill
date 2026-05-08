# ConnectRPC Python Backend Reference

> **Status**: Beta. Keep examples conservative and prefer generated classes from `*_connect.py`.
> **Recommended path**: Async ASGI service + generated client/server classes.

## Defaults

- Treat Python as a **beta / constrained** ConnectRPC track
- Prefer **ASGI** for new services
- Generate `*_pb2.py`, `*_pb2.pyi`, and `*_connect.py`
- Use generated application/client classes from `*_connect.py`
- Do not present Python as feature-equivalent to the Go stack unless verified for your specific protocol/runtime path

## Installation

```bash
pip install connectrpc
```

Optional extras:

```bash
pip install connectrpc[grpc]
pip install connectrpc[otel]
pip install connectrpc[grpc,otel]
```

## Code Generation

Use Buf to generate protobuf types, type hints, and ConnectRPC service/client wrappers.

```yaml
# buf.gen.yaml
version: v2
plugins:
  - remote: buf.build/protocolbuffers/python
    out: gen/python
  - remote: buf.build/protocolbuffers/pyi
    out: gen/python
  - remote: buf.build/connectrpc/python
    out: gen/python
```

Run generation:

```bash
buf generate
```

Generated output typically looks like:

```text
gen/python/
  user_pb2.py
  user_pb2.pyi
  user_connect.py
```

## Async ASGI Service (recommended)

```python
from connectrpc.request import RequestContext
from gen.python.user_pb2 import GetUserRequest, GetUserResponse
from gen.python.user_connect import UserService, UserServiceASGIApplication


class UserServiceImpl(UserService):
    async def get_user(self, request: GetUserRequest, ctx: RequestContext) -> GetUserResponse:
        return GetUserResponse(message=f"Hello, {request.id}")


app = UserServiceASGIApplication(UserServiceImpl())

# Run with uvicorn or hypercorn
# uvicorn server:app --port 8080
```

## Sync WSGI Service

Use this only when you need a synchronous deployment model.

```python
from typing import Iterator

from connectrpc.request import RequestContext
from gen.python.user_pb2 import GetUserRequest, GetUserResponse, ListUsersResponse
from gen.python.user_connect import UserService, UserServiceWSGIApplication


class UserServiceSync(UserService):
    def get_user(self, request: GetUserRequest, ctx: RequestContext) -> GetUserResponse:
        return GetUserResponse(message=f"Hello, {request.id}")

    def list_users(self, request: GetUserRequest, ctx: RequestContext) -> Iterator[ListUsersResponse]:
        yield ListUsersResponse(message="Alice")
        yield ListUsersResponse(message="Bob")


app = UserServiceWSGIApplication(UserServiceSync())

# gunicorn server:app
```

## Async Client

Prefer the generated client class from `*_connect.py`.

```python
from gen.python.user_pb2 import GetUserRequest
from gen.python.user_connect import UserServiceClient


async def main() -> None:
    async with UserServiceClient("https://api.example.com") as client:
        response = await client.get_user(GetUserRequest(id="123"))
        print(response.message)
```

### Advanced async client options

When you need protocol or codec control, generated clients accept extra options.

```python
from connectrpc.code import Code
from connectrpc.codec import proto_json_codec
from connectrpc.compression.brotli import BrotliCompression
from connectrpc.errors import ConnectError
from connectrpc.protocol import ProtocolType
from gen.python.user_pb2 import GetUserRequest
from gen.python.user_connect import UserServiceClient


async def main() -> None:
    async with UserServiceClient(
        "https://api.example.com",
        protocol=ProtocolType.CONNECT,
        codec=proto_json_codec(),
        timeout_ms=5_000,
        accept_compression=[BrotliCompression()],
    ) as client:
        try:
            response = await client.get_user(GetUserRequest(id="123"))
            print(response.message)
        except ConnectError as err:
            if err.code == Code.DEADLINE_EXCEEDED:
                print("timed out")
            else:
                print(f"RPC error [{err.code}]: {err.message}")
```

## Error Handling

```python
from connectrpc.code import Code
from connectrpc.errors import ConnectError

raise ConnectError(Code.INVALID_ARGUMENT, "id is required")
raise ConnectError(Code.NOT_FOUND, "user not found")
raise ConnectError(Code.PERMISSION_DENIED, "insufficient permissions")
```

With error details:

```python
from google.rpc import error_details_pb2
from connectrpc.code import Code
from connectrpc.errors import ConnectError

detail = error_details_pb2.ErrorInfo(
    reason="USER_NOT_FOUND",
    domain="myapp.v1",
    metadata={"user_id": request.id},
)

raise ConnectError(Code.NOT_FOUND, "user not found", details=[detail])
```

## Request Context

Use `RequestContext` for metadata, timeouts, and response headers/trailers.

```python
from connectrpc.request import RequestContext


async def get_user(self, request, ctx: RequestContext):
    auth = ctx.request_headers().get("authorization", "")
    ctx.response_headers().add("x-request-id", "req-001")
    return ...
```

## Interceptors

Start with lightweight metadata interceptors. Only move to full unary interceptors when you need request/response interception.

```python
from connectrpc.request import RequestContext
from connectrpc.errors import ConnectError
from connectrpc.code import Code


class LoggingInterceptor:
    async def on_start(self, ctx: RequestContext) -> None:
        print(f"Handling {ctx.method().name} request")

    async def on_end(self, token: None, ctx: RequestContext, error: Exception | None) -> None:
        if error:
            print(f"Failed {ctx.method().name}: {error}")


class AuthInterceptor:
    async def intercept_unary(self, call_next, request, ctx: RequestContext):
        token = ctx.request_headers().get("authorization", "")
        if not token.startswith("Bearer "):
            raise ConnectError(Code.UNAUTHENTICATED, "missing bearer token")
        return await call_next(request, ctx)


app = UserServiceASGIApplication(
    UserServiceImpl(),
    interceptors=[LoggingInterceptor(), AuthInterceptor()],
)
```

## OpenTelemetry

```python
from connectrpc_otel import OpenTelemetryInterceptor
from gen.python.user_connect import UserServiceASGIApplication

app = UserServiceASGIApplication(
    UserServiceImpl(),
    interceptors=[OpenTelemetryInterceptor()],
)
```

## FastAPI / Starlette Mounting

Mount the generated ASGI application into a larger app when needed.

```python
from fastapi import FastAPI
from gen.python.user_connect import UserServiceASGIApplication

fastapi_app = FastAPI()
connect_app = UserServiceASGIApplication(UserServiceImpl())

fastapi_app.mount("/", connect_app)
```

## Testing

Prefer ASGI-level tests around the generated application class.

```python
import pytest
from httpx import ASGITransport, AsyncClient
from gen.python.user_connect import UserServiceASGIApplication


@pytest.fixture
def app():
    return UserServiceASGIApplication(UserServiceImpl())


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
```

## Python-Specific Gotchas

- Keep the beta label explicit in the skill.
- Prefer generated `*_connect.py` classes over hand-rolled generic wrappers.
- Keep examples conservative and exact; avoid inventing convenience APIs.
- If you need a deeply customized runtime path, verify it against the current upstream README before teaching it.
