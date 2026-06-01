# ConnectRPC Skill

[![skills.sh](https://skills.sh/b/owezzy/connectrpc-skill)](https://skills.sh/owezzy/connectrpc-skill)

Build, configure, and debug ConnectRPC services and clients across Go, Python, and TypeScript (React/Angular), with Buf-based protobuf generation and practical guidance for transport choice, interceptors, and cross-language RPC workflows.

## Install

```bash
npx skills add owezzy/connectrpc-skill
```

## When this skill should trigger

Use this skill when the user is:

- building a ConnectRPC service from `.proto` files
- generating clients or handlers with Buf
- working with `connect-go`, `connect-es`, `connect-query`, or `connect-python`
- deciding between Connect, gRPC, and gRPC-Web
- wiring ConnectRPC into React or Angular
- debugging streaming, metadata, CORS, or code generation issues

## Coverage

- **Go** backend: handlers, interceptors, streaming, testing, CORS, reflection
- **TypeScript** frontend: React (connect-query + TanStack), Angular (manual DI), interceptors, error handling
- **Python** backend: ASGI/WSGI, interceptors, OpenTelemetry, FastAPI mount
- **Buf tooling**: lint, breaking changes, BSR, managed mode, polyglot code generation, CI/CD

## Structure

```
SKILL.md              — Routing-first workflow, defaults, gotchas, troubleshooting
references/
  go.md               — Go backend patterns
  typescript.md       — TypeScript frontend (React + Angular)
  python.md           — Python backend patterns
  buf-tooling.md      — Buf CLI and proto toolchain
scripts/
  gen.sh              — portable buf generate helper for a target repo
  validate-proto.sh   — portable buf lint + breaking helper for a target repo
evals/
  evals.json          — Starter skill evaluation prompts and assertions
```

## Scripts

The skill now ships two portable shell scripts for use against a real ConnectRPC repository:

```bash
./scripts/gen.sh --help
./scripts/validate-proto.sh --help
```

Examples:

```bash
./scripts/gen.sh --dir /path/to/repo
./scripts/validate-proto.sh --dir /path/to/repo --against '.git#branch=main'
```

They are non-interactive, idempotent, and emit JSON to stdout so an agent can call them safely.

## Evaluation

This repo includes a starter evaluation file:

```text
evals/evals.json
```

Use it to compare the skill with and without activation, then extend the prompts and assertions as the skill evolves.

## Author

Owen Adirah ([@owezzy](https://github.com/owezzy))

## License

MIT
