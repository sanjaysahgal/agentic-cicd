# agentic-cicd — Agent Entry Point

## What is this repo?
agentic-cicd is a generic, app-agnostic CI/CD pipeline platform. It owns all pipeline logic for the agentic app portfolio. Individual apps own only config.

This is not an application repo. No business logic lives here.

## What can be written here?

| Path | What goes here |
|---|---|
| `.github/workflows/` | Reusable workflows (`workflow_call`) |
| `actions/*/action.yml` | Composite actions |
| `docs/` | Integration guides and onboarding docs |

## How apps integrate

```yaml
jobs:
  ci:
    uses: sanjaysahgal/agentic-cicd/.github/workflows/nextjs-pipeline.yml@main
    with:
      node-version: '20'
      package-manager: 'pnpm'
    secrets: inherit
```

## Read before working here
- `docs/integration-guide.md` — full input/output contract
- `docs/adding-a-new-app.md` — onboarding checklist
- `README.md` — architecture overview
