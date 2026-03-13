#!/bin/bash
set -e

echo "Creating agentic-cicd directory structure..."
mkdir -p .github/workflows actions/setup-pnpm actions/deploy-vercel actions/notify-slack actions/betterstack-heartbeat docs

echo "Creating .github/workflows/nextjs-pipeline.yml..."
cat > .github/workflows/nextjs-pipeline.yml << 'HEREDOC'
name: Next.js CI Pipeline

on:
  workflow_call:
    inputs:
      node-version:
        description: 'Node.js version'
        type: string
        default: '20'
      package-manager:
        description: 'Package manager (pnpm or npm)'
        type: string
        default: 'pnpm'
      lint-command:
        description: 'Lint command'
        type: string
        default: 'pnpm lint'
      typecheck-command:
        description: 'TypeScript typecheck command'
        type: string
        default: 'pnpm typecheck'
      test-command:
        description: 'Unit + integration test command'
        type: string
        default: 'pnpm test'
      build-command:
        description: 'Production build command'
        type: string
        default: 'pnpm build'
      lighthouse-enabled:
        description: 'Run Lighthouse CI after build'
        type: boolean
        default: true
      percy-enabled:
        description: 'Run Percy visual regression'
        type: boolean
        default: false
      working-directory:
        description: 'Working directory for all commands'
        type: string
        default: '.'
    secrets:
      PERCY_TOKEN:
        required: false

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup pnpm + Node
        uses: sanjaysahgal/agentic-cicd/actions/setup-pnpm@main
        with:
          node-version: ${{ inputs.node-version }}
          package-manager: ${{ inputs.package-manager }}
          working-directory: ${{ inputs.working-directory }}
      - name: Run lint
        working-directory: ${{ inputs.working-directory }}
        run: ${{ inputs.lint-command }}

  typecheck:
    name: TypeScript
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup pnpm + Node
        uses: sanjaysahgal/agentic-cicd/actions/setup-pnpm@main
        with:
          node-version: ${{ inputs.node-version }}
          package-manager: ${{ inputs.package-manager }}
          working-directory: ${{ inputs.working-directory }}
      - name: Run typecheck
        working-directory: ${{ inputs.working-directory }}
        run: ${{ inputs.typecheck-command }}

  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup pnpm + Node
        uses: sanjaysahgal/agentic-cicd/actions/setup-pnpm@main
        with:
          node-version: ${{ inputs.node-version }}
          package-manager: ${{ inputs.package-manager }}
          working-directory: ${{ inputs.working-directory }}
      - name: Run tests
        working-directory: ${{ inputs.working-directory }}
        run: ${{ inputs.test-command }}

  build:
    name: Build
    runs-on: ubuntu-latest
    needs: [lint, typecheck, test]
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup pnpm + Node
        uses: sanjaysahgal/agentic-cicd/actions/setup-pnpm@main
        with:
          node-version: ${{ inputs.node-version }}
          package-manager: ${{ inputs.package-manager }}
          working-directory: ${{ inputs.working-directory }}
      - name: Run build
        working-directory: ${{ inputs.working-directory }}
        run: ${{ inputs.build-command }}
      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: build-output
          path: ${{ inputs.working-directory }}/.next
          retention-days: 1
          if-no-files-found: ignore
HEREDOC

echo "Creating .github/workflows/deploy-vercel-preview.yml..."
cat > .github/workflows/deploy-vercel-preview.yml << 'HEREDOC'
name: Deploy Vercel Preview

on:
  workflow_call:
    inputs:
      node-version:
        description: 'Node.js version'
        type: string
        default: '20'
      package-manager:
        description: 'Package manager (pnpm or npm)'
        type: string
        default: 'pnpm'
      working-directory:
        description: 'Working directory'
        type: string
        default: '.'
      vercel-org-id:
        description: 'Vercel organization ID'
        type: string
        required: false
      vercel-project-id:
        description: 'Vercel project ID'
        type: string
        required: false
    secrets:
      VERCEL_TOKEN:
        required: true
      VERCEL_ORG_ID:
        required: false
      VERCEL_PROJECT_ID:
        required: false
    outputs:
      preview-url:
        description: 'Vercel preview deployment URL'
        value: ${{ jobs.deploy-preview.outputs.preview-url }}

jobs:
  deploy-preview:
    name: Deploy Preview
    runs-on: ubuntu-latest
    outputs:
      preview-url: ${{ steps.deploy.outputs.preview-url }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup pnpm + Node
        uses: sanjaysahgal/agentic-cicd/actions/setup-pnpm@main
        with:
          node-version: ${{ inputs.node-version }}
          package-manager: ${{ inputs.package-manager }}
          working-directory: ${{ inputs.working-directory }}
      - name: Deploy to Vercel preview
        id: deploy
        uses: sanjaysahgal/agentic-cicd/actions/deploy-vercel@main
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID || inputs.vercel-org-id }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID || inputs.vercel-project-id }}
          environment: preview
          working-directory: ${{ inputs.working-directory }}
      - name: Comment preview URL on PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const previewUrl = '${{ steps.deploy.outputs.preview-url }}';
            const body = `## Vercel Preview Deployment\n\n✅ Deployed to: ${previewUrl}\n\n_Commit: ${{ github.sha }}_`;
            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
            });
            const botComment = comments.find(c =>
              c.user.type === 'Bot' && c.body.includes('Vercel Preview Deployment')
            );
            if (botComment) {
              await github.rest.issues.updateComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                comment_id: botComment.id,
                body,
              });
            } else {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.issue.number,
                body,
              });
            }
HEREDOC

echo "Creating .github/workflows/deploy-vercel-production.yml..."
cat > .github/workflows/deploy-vercel-production.yml << 'HEREDOC'
name: Deploy Vercel Production

on:
  workflow_call:
    inputs:
      node-version:
        description: 'Node.js version'
        type: string
        default: '20'
      package-manager:
        description: 'Package manager (pnpm or npm)'
        type: string
        default: 'pnpm'
      working-directory:
        description: 'Working directory'
        type: string
        default: '.'
      app-name:
        description: 'App name for Slack notification'
        type: string
        required: true
      notify-slack:
        description: 'Send Slack notification on deploy'
        type: boolean
        default: true
      betterstack-heartbeat:
        description: 'Ping BetterStack heartbeat after deploy'
        type: boolean
        default: true
    secrets:
      VERCEL_TOKEN:
        required: true
      VERCEL_ORG_ID:
        required: false
      VERCEL_PROJECT_ID:
        required: false
      SLACK_WEBHOOK_URL:
        required: false
      BETTERSTACK_HEARTBEAT_URL:
        required: false
    outputs:
      production-url:
        description: 'Vercel production deployment URL'
        value: ${{ jobs.deploy-production.outputs.production-url }}

jobs:
  deploy-production:
    name: Deploy Production
    runs-on: ubuntu-latest
    environment: production
    outputs:
      production-url: ${{ steps.deploy.outputs.production-url }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup pnpm + Node
        uses: sanjaysahgal/agentic-cicd/actions/setup-pnpm@main
        with:
          node-version: ${{ inputs.node-version }}
          package-manager: ${{ inputs.package-manager }}
          working-directory: ${{ inputs.working-directory }}
      - name: Deploy to Vercel production
        id: deploy
        uses: sanjaysahgal/agentic-cicd/actions/deploy-vercel@main
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          environment: production
          working-directory: ${{ inputs.working-directory }}
      - name: Notify Slack on success
        if: ${{ inputs.notify-slack && secrets.SLACK_WEBHOOK_URL != '' }}
        uses: sanjaysahgal/agentic-cicd/actions/notify-slack@main
        with:
          webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
          status: success
          message: |
            *${{ inputs.app-name }}* deployed to production
            URL: ${{ steps.deploy.outputs.production-url }}
            Commit: `${{ github.sha }}`
            Author: ${{ github.actor }}
      - name: Ping BetterStack heartbeat
        if: ${{ inputs.betterstack-heartbeat && secrets.BETTERSTACK_HEARTBEAT_URL != '' }}
        uses: sanjaysahgal/agentic-cicd/actions/betterstack-heartbeat@main
        with:
          heartbeat-url: ${{ secrets.BETTERSTACK_HEARTBEAT_URL }}
      - name: Notify Slack on failure
        if: failure() && inputs.notify-slack && secrets.SLACK_WEBHOOK_URL != ''
        uses: sanjaysahgal/agentic-cicd/actions/notify-slack@main
        with:
          webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
          status: failure
          message: |
            *${{ inputs.app-name }}* production deploy FAILED
            Commit: `${{ github.sha }}`
            Author: ${{ github.actor }}
            Run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
HEREDOC

echo "Creating .github/workflows/post-deploy-checks.yml..."
cat > .github/workflows/post-deploy-checks.yml << 'HEREDOC'
name: Post-Deploy Checks

on:
  workflow_call:
    inputs:
      deployment-url:
        description: 'URL of the deployed app to test against'
        type: string
        required: true
      environment:
        description: 'Deployment environment (preview or production)'
        type: string
        default: 'production'
      smoke-test-command:
        description: 'Smoke test command (leave empty to skip)'
        type: string
        default: ''
      lighthouse-enabled:
        description: 'Run Lighthouse CI'
        type: boolean
        default: true
      lighthouse-budget-path:
        description: 'Path to Lighthouse budget JSON file'
        type: string
        default: '.lighthouserc.json'
      percy-enabled:
        description: 'Run Percy visual regression'
        type: boolean
        default: false
      node-version:
        description: 'Node.js version'
        type: string
        default: '20'
      package-manager:
        description: 'Package manager'
        type: string
        default: 'pnpm'
    secrets:
      PERCY_TOKEN:
        required: false

jobs:
  smoke-tests:
    name: Smoke Tests
    runs-on: ubuntu-latest
    if: inputs.smoke-test-command != ''
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup pnpm + Node
        uses: sanjaysahgal/agentic-cicd/actions/setup-pnpm@main
        with:
          node-version: ${{ inputs.node-version }}
          package-manager: ${{ inputs.package-manager }}
      - name: Run smoke tests
        env:
          DEPLOYMENT_URL: ${{ inputs.deployment-url }}
        run: ${{ inputs.smoke-test-command }}

  lighthouse:
    name: Lighthouse CI
    runs-on: ubuntu-latest
    if: inputs.lighthouse-enabled
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup pnpm + Node
        uses: sanjaysahgal/agentic-cicd/actions/setup-pnpm@main
        with:
          node-version: ${{ inputs.node-version }}
          package-manager: ${{ inputs.package-manager }}
      - name: Install Lighthouse CI
        run: npm install -g @lhci/cli@0.14.x
      - name: Run Lighthouse CI
        env:
          LHCI_TARGET_URL: ${{ inputs.deployment-url }}
        run: |
          if [ -f "${{ inputs.lighthouse-budget-path }}" ]; then
            lhci autorun --config=${{ inputs.lighthouse-budget-path }}
          else
            lhci autorun \
              --collect.url=${{ inputs.deployment-url }} \
              --assert.preset=lighthouse:recommended \
              --assert.assertions.categories:performance=["warn",{"minScore":0.8}] \
              --assert.assertions.categories:accessibility=["error",{"minScore":0.9}] \
              --assert.assertions.categories:best-practices=["warn",{"minScore":0.9}] \
              --assert.assertions.categories:seo=["warn",{"minScore":0.9}]
          fi

  percy:
    name: Percy Visual Regression
    runs-on: ubuntu-latest
    if: inputs.percy-enabled
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup pnpm + Node
        uses: sanjaysahgal/agentic-cicd/actions/setup-pnpm@main
        with:
          node-version: ${{ inputs.node-version }}
          package-manager: ${{ inputs.package-manager }}
      - name: Run Percy snapshot
        env:
          PERCY_TOKEN: ${{ secrets.PERCY_TOKEN }}
          DEPLOYMENT_URL: ${{ inputs.deployment-url }}
        run: |
          npx percy snapshot --base-url=${{ inputs.deployment-url }} \
            --snapshot-files='tests/snapshots/**/*.yml' \
            2>/dev/null || npx percy exec -- pnpm test:snapshots
HEREDOC

echo "Creating actions/setup-pnpm/action.yml..."
cat > actions/setup-pnpm/action.yml << 'HEREDOC'
name: Setup pnpm + Node
description: Sets up Node.js and pnpm with dependency cache

inputs:
  node-version:
    description: 'Node.js version'
    required: false
    default: '20'
  package-manager:
    description: 'Package manager: pnpm or npm'
    required: false
    default: 'pnpm'
  pnpm-version:
    description: 'pnpm version to install'
    required: false
    default: '9'
  working-directory:
    description: 'Working directory for install'
    required: false
    default: '.'

runs:
  using: composite
  steps:
    - name: Setup pnpm
      if: inputs.package-manager == 'pnpm'
      uses: pnpm/action-setup@v4
      with:
        version: ${{ inputs.pnpm-version }}
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: ${{ inputs.node-version }}
        cache: ${{ inputs.package-manager }}
        cache-dependency-path: ${{ inputs.working-directory }}/pnpm-lock.yaml
    - name: Install dependencies (pnpm)
      if: inputs.package-manager == 'pnpm'
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: pnpm install --frozen-lockfile
    - name: Install dependencies (npm)
      if: inputs.package-manager == 'npm'
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: npm ci
HEREDOC

echo "Creating actions/deploy-vercel/action.yml..."
cat > actions/deploy-vercel/action.yml << 'HEREDOC'
name: Deploy to Vercel
description: Deploys to Vercel using the Vercel CLI. Outputs the deployment URL.

inputs:
  vercel-token:
    description: 'Vercel API token'
    required: true
  vercel-org-id:
    description: 'Vercel organization ID'
    required: true
  vercel-project-id:
    description: 'Vercel project ID'
    required: true
  environment:
    description: 'Deployment environment: preview or production'
    required: false
    default: 'preview'
  working-directory:
    description: 'Directory to deploy from'
    required: false
    default: '.'

outputs:
  preview-url:
    description: 'Deployment URL (preview)'
    value: ${{ steps.deploy.outputs.url }}
  production-url:
    description: 'Deployment URL (production)'
    value: ${{ steps.deploy.outputs.url }}

runs:
  using: composite
  steps:
    - name: Install Vercel CLI
      shell: bash
      run: npm install -g vercel@latest
    - name: Pull Vercel environment info
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        VERCEL_TOKEN: ${{ inputs.vercel-token }}
        VERCEL_ORG_ID: ${{ inputs.vercel-org-id }}
        VERCEL_PROJECT_ID: ${{ inputs.vercel-project-id }}
      run: |
        if [ "${{ inputs.environment }}" = "production" ]; then
          vercel pull --yes --environment=production --token=${{ inputs.vercel-token }}
        else
          vercel pull --yes --environment=preview --token=${{ inputs.vercel-token }}
        fi
    - name: Build project artifacts
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        VERCEL_TOKEN: ${{ inputs.vercel-token }}
        VERCEL_ORG_ID: ${{ inputs.vercel-org-id }}
        VERCEL_PROJECT_ID: ${{ inputs.vercel-project-id }}
      run: |
        if [ "${{ inputs.environment }}" = "production" ]; then
          vercel build --prod --token=${{ inputs.vercel-token }}
        else
          vercel build --token=${{ inputs.vercel-token }}
        fi
    - name: Deploy to Vercel
      id: deploy
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        VERCEL_TOKEN: ${{ inputs.vercel-token }}
        VERCEL_ORG_ID: ${{ inputs.vercel-org-id }}
        VERCEL_PROJECT_ID: ${{ inputs.vercel-project-id }}
      run: |
        if [ "${{ inputs.environment }}" = "production" ]; then
          DEPLOY_URL=$(vercel deploy --prebuilt --prod --token=${{ inputs.vercel-token }})
        else
          DEPLOY_URL=$(vercel deploy --prebuilt --token=${{ inputs.vercel-token }})
        fi
        echo "url=$DEPLOY_URL" >> $GITHUB_OUTPUT
        echo "Deployed to: $DEPLOY_URL"
HEREDOC

echo "Creating actions/notify-slack/action.yml..."
cat > actions/notify-slack/action.yml << 'HEREDOC'
name: Notify Slack
description: Posts a notification to a Slack channel via incoming webhook.

inputs:
  webhook-url:
    description: 'Slack incoming webhook URL'
    required: true
  status:
    description: 'Status: success, failure, or info'
    required: false
    default: 'info'
  message:
    description: 'Message body (markdown supported in Slack mrkdwn format)'
    required: true

runs:
  using: composite
  steps:
    - name: Determine color
      id: color
      shell: bash
      run: |
        case "${{ inputs.status }}" in
          success) echo "color=#36a64f" >> $GITHUB_OUTPUT ;;
          failure) echo "color=#ff0000" >> $GITHUB_OUTPUT ;;
          *)       echo "color=#439fe0" >> $GITHUB_OUTPUT ;;
        esac
    - name: Post Slack message
      shell: bash
      run: |
        STATUS_EMOJI=""
        case "${{ inputs.status }}" in
          success) STATUS_EMOJI="✅" ;;
          failure) STATUS_EMOJI="❌" ;;
          *)       STATUS_EMOJI="ℹ️" ;;
        esac
        MESSAGE="${STATUS_EMOJI} ${{ inputs.message }}"
        curl -s -X POST "${{ inputs.webhook-url }}" \
          -H "Content-Type: application/json" \
          -d "{
            \"attachments\": [
              {
                \"color\": \"${{ steps.color.outputs.color }}\",
                \"text\": $(echo "$MESSAGE" | jq -Rs .),
                \"footer\": \"agentic-cicd | ${{ github.repository }}\",
                \"ts\": $(date +%s)
              }
            ]
          }"
HEREDOC

echo "Creating actions/betterstack-heartbeat/action.yml..."
cat > actions/betterstack-heartbeat/action.yml << 'HEREDOC'
name: BetterStack Heartbeat
description: Pings a BetterStack heartbeat URL to confirm a successful production deploy.

inputs:
  heartbeat-url:
    description: 'BetterStack heartbeat URL'
    required: true

runs:
  using: composite
  steps:
    - name: Ping BetterStack heartbeat
      shell: bash
      run: |
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${{ inputs.heartbeat-url }}")
        if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
          echo "BetterStack heartbeat pinged successfully (HTTP $HTTP_STATUS)"
        else
          echo "Warning: BetterStack heartbeat returned HTTP $HTTP_STATUS" >&2
          exit 0
        fi
HEREDOC

echo "Creating README.md..."
cat > README.md << 'HEREDOC'
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
HEREDOC

echo "Creating CLAUDE.md..."
cat > CLAUDE.md << 'HEREDOC'
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
HEREDOC

echo "All files created successfully!"
echo ""
echo "Next steps:"
echo "  git add ."
echo "  git commit -m 'Initial CI/CD platform: reusable workflows for the agentic app portfolio'"
echo "  git remote add origin https://github.com/sanjaysahgal/agentic-cicd.git"
echo "  git push -u origin main"
