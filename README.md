# agentic-cicd

Generic CI/CD pipeline platform for the agentic app portfolio.

## Architecture

```
agentic-cicd (this repo)              any-app (e.g. agentic-health360)
─────────────────────────             ─────────────────────────────────
.github/workflows/                    .github/workflows/
  nextjs-pipeline.yml      ◄──────     ci.yml (calls nextjs-pipeline)
  deploy-vercel-preview.yml ◄────      deploy.yml (calls deploy workflows)
  deploy-vercel-production.yml
  post-deploy-checks.yml

actions/
  setup-pnpm/
  deploy-vercel/
  notify-slack/
  betterstack-heartbeat/
```

Apps own config only. This repo owns logic only.

## Reusable Workflows

| Workflow | Description |
|---|---|
| `nextjs-pipeline.yml` | Full CI: lint, typecheck, test, build |
| `deploy-vercel-preview.yml` | Deploy Vercel preview on PR |
| `deploy-vercel-production.yml` | Deploy Vercel production on main merge |
| `post-deploy-checks.yml` | Smoke tests, Lighthouse CI, Percy |

## Required Secrets (set in calling repo)

| Secret | Used by |
|---|---|
| `VERCEL_TOKEN` | deploy-vercel action |
| `VERCEL_ORG_ID` | deploy-vercel action |
| `VERCEL_PROJECT_ID` | deploy-vercel action |
| `SLACK_WEBHOOK_URL` | notify-slack action |
| `BETTERSTACK_HEARTBEAT_URL` | betterstack-heartbeat action |
| `PERCY_TOKEN` | post-deploy-checks workflow |

See `docs/adding-a-new-app.md` for the full onboarding checklist.
