# ConnectRPC Skill

Build type-safe RPC services with [ConnectRPC](https://connectrpc.com) across Go, Python, and TypeScript (Angular/React).

## Install

```bash
npx skills add owezzy/connectrpc-skill
```

## Coverage

- **Go** backend: handlers, interceptors, streaming, testing, CORS, reflection
- **TypeScript** frontend: React (connect-query + TanStack), Angular (manual DI), interceptors, error handling
- **Python** backend: ASGI/WSGI, interceptors, OpenTelemetry, FastAPI mount
- **Buf tooling**: lint, breaking changes, BSR, managed mode, polyglot code generation, CI/CD

## Structure

```
SKILL.md              — Core workflow and quick reference
references/
  go.md               — Go backend patterns
  typescript.md       — TypeScript frontend (React + Angular)
  python.md           — Python backend patterns
  buf-tooling.md      — Buf CLI and proto toolchain
```

## Author

Owen Adirah ([@owezzy](https://github.com/owezzy))

## License

MIT
