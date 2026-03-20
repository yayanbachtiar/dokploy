# Dokploy - Project Context

## Project Overview

Dokploy is a **self-hostable Platform as a Service (PaaS)** that simplifies the deployment and management of applications and databases. It serves as an open-source alternative to Vercel, Heroku, and Netlify.

### Key Features
- Deploy applications (Node.js, PHP, Python, Go, Ruby, etc.)
- Database management (MySQL, PostgreSQL, MongoDB, MariaDB, Redis)
- Automated backups
- Docker Compose support
- Multi-node clustering via Docker Swarm
- One-click templates (Plausible, Pocketbase, Calcom, etc.)
- Traefik integration for routing/load balancing
- Real-time monitoring (CPU, memory, storage, network)
- CLI/API for management
- Notifications (Slack, Discord, Telegram, Email)
- Multi-server support

## Tech Stack

### Core Technologies
- **Runtime:** Node.js v24.4.0
- **Package Manager:** pnpm v10.22.0
- **Monorepo:** pnpm workspaces
- **Language:** TypeScript

### Frameworks & Libraries
- **Frontend:** Next.js 16, React 18, Tailwind CSS, Radix UI
- **Backend:** tRPC, Hono (API), Node.js HTTP server
- **Database:** PostgreSQL with Drizzle ORM
- **Authentication:** Better Auth
- **Container Management:** Dockerode
- **AI Integration:** Vercel AI SDK (multiple providers)
- **Form Handling:** React Hook Form, Zod
- **Charts:** Recharts
- **Code Editor:** CodeMirror, Xterm.js

### Tooling
- **Linting/Formatting:** Biome
- **Testing:** Vitest
- **Build:** esbuild, Next.js build
- **Database Migrations:** Drizzle Kit

## Project Structure

```
dokploy/
├── apps/
│   ├── dokploy/          # Main Next.js application (dashboard & server)
│   ├── api/              # API service (Hono + Inngest)
│   ├── monitoring/       # Monitoring service
│   └── schedules/        # Scheduled tasks service
├── packages/
│   └── server/           # Shared server utilities & services
├── .github/              # GitHub workflows, templates
├── Dockerfile*           # Multiple Docker configurations
└── package.json          # Root workspace configuration
```

### Key Directories in `apps/dokploy/`
- `server/` - Backend server with WebSocket handlers for logs, terminals, stats
- `components/` - React UI components
- `pages/` - Next.js pages and API routes
- `drizzle/` - Database schema and migrations
- `templates/` - One-click deploy templates
- `__test__/` - Test suites organized by feature

## Building and Running

### Prerequisites
- **Docker** (required for full functionality)
- **Node.js v24.4.0** (use `nvm use` with `.nvmrc`)
- **pnpm v10.22.0+**

### Initial Setup

```bash
# Clone the repository (use 'canary' branch for development)
git clone https://github.com/dokploy/dokploy.git
cd dokploy

# Install dependencies
pnpm install

# Copy environment file
cp apps/dokploy/.env.example apps/dokploy/.env

# Run setup (creates required services and files)
pnpm run dokploy:setup

# Switch server to development mode
pnpm run server:script
```

### Development

```bash
# Start development server (runs on http://localhost:3000)
pnpm run dokploy:dev

# Alternative: run server package in dev mode
pnpm run server:dev
```

### Building

```bash
# Build all packages
pnpm run build

# Build only dokploy app
pnpm run dokploy:build

# Build server package
pnpm run server:build

# Type check all packages
pnpm run typecheck
```

### Docker

```bash
# Build Docker image
pnpm run docker:build:canary

# Push Docker image
pnpm run docker:push
```

### Testing

```bash
# Run tests
pnpm run test
```

### Code Quality

```bash
# Format and lint
pnpm run format-and-lint

# Fix formatting and lint issues
pnpm run format-and-lint:fix

# Check only
pnpm run check
```

### Database Commands

```bash
# Generate migrations
pnpm run migration:generate

# Run migrations
pnpm run migration:run

# Push schema to database
pnpm run db:push

# Open Drizzle Studio
pnpm run studio

# Drop migrations
pnpm run migration:drop
```

### Utilities

```bash
# Reset password
pnpm run reset-password

# Reset 2FA
pnpm run reset-2fa

# Generate OpenAPI spec
pnpm run generate:openapi
```

## Development Conventions

### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

### Code Style
- **Formatter/Linter:** Biome (configured in `biome.json`)
- **TypeScript:** Strict mode enabled
- **Path Aliases:** `@/*` for app root, `@dokploy/server/*` for server package

### Branch Strategy
- `canary` branch: Source of truth for development (merge PRs here)
- `main` branch: Stable releases only

### Pull Request Guidelines
- **Testing is mandatory** - verify changes locally before submitting
- Each PR should address a single problem/feature
- Link related issues in PR description (e.g., `Fixes #123`)
- Provide clear descriptions of changes
- Include screenshots/videos when applicable
- Large features must be discussed in a GitHub issue first

### Environment Variables
- Development: `.env` in `apps/dokploy/`
- Production: `.env.production` in `apps/dokploy/`

## Architecture Notes

### Server Architecture
- Custom HTTP server wrapping Next.js
- WebSocket servers for:
  - Container logs streaming
  - Terminal sessions
  - Docker stats monitoring
  - Deployment logs
- Traefik integration for routing
- Cron jobs for backups and scheduled tasks

### Database
- PostgreSQL as primary database
- Drizzle ORM for type-safe queries
- Migration-based schema management

### Authentication
- Better Auth with support for:
  - Email/password
  - SSO providers
  - API keys
  - 2FA

### Container Management
- Docker Swarm for orchestration
- Dockerode for Docker API interaction
- Support for multiple deployment sources:
  - Git (GitHub, GitLab, Bitbucket, Gitea)
  - Docker images
  - Docker Compose
  - Buildpacks/Nixpacks

## Important Files

| File | Purpose |
|------|---------|
| `apps/dokploy/server/server.ts` | Main server entry point |
| `apps/dokploy/next.config.mjs` | Next.js configuration |
| `packages/server/src/index.ts` | Server package exports |
| `biome.json` | Linting/formatting rules |
| `pnpm-workspace.yaml` | Workspace configuration |
| `apps/dokploy/drizzle/` | Database schema |

## External Dependencies

### Required System Packages
- Docker Engine
- Docker Compose
- Traefik (auto-managed)

### Optional Build Tools
- Nixpacks
- Railpack
- Buildpacks (Pack CLI)

## Contributing

1. Create branch from `canary`
2. Make changes with proper tests
3. Follow commit message convention
4. Submit PR to `canary` branch
5. Wait for review and merge

For detailed guidelines, see [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Related Repositories

- **Templates:** https://github.com/Dokploy/templates
- **Documentation:** https://github.com/Dokploy/website

## Support

- **Discord:** https://discord.gg/2tBnJ3jDJc
- **Documentation:** https://docs.dokploy.com
- **GitHub Sponsors:** https://github.com/sponsors/Siumauricio
