<!-- SYNC: This file is duplicated in dev-agent/references/grounding-guide.md.
     Keep both copies in sync. Changes here must be applied to the other copy. -->

# Grounding Guide

Before writing any code, detect the issue's domain and pull in the right
documentation. Using outdated patterns or wrong APIs is the most common source
of rework. Grounding prevents this.

## Domain Detection

Read the issue title, body, labels, and any linked issues. Look for these signals:

| Domain | Signals | Grounding Action |
|--------|---------|-----------------|
| GCP / Firebase / Cloud Run | `gcloud`, `firebase`, `Firestore`, `IAM`, `Cloud Run`, `.env`, deployment configs, GCP service names | Google Developer Knowledge MCP |
| ADK (Agent Development Kit) | `agent`, `ADK`, `orchestrator`, `tool definition`, `callback`, `session`, agent code paths | ADK MCP + ADK skills |
| Python package / library | Import names, package names in `pyproject.toml`, version bumps, dependency changes | Context7 MCP |
| JavaScript / Node package | `package.json` changes, npm/yarn packages, React/Vue/Angular libraries | Context7 MCP |
| Frontend / UI creation | `component`, `page`, `CSS`, `React`, `TypeScript`, layout, design, styling, new UI elements | `/frontend-design` skill |
| UI verification | Visual regression, layout changes, screenshot comparison, "verify it looks right" | `/playwright-cli` skill |

## How to Use Each Source

### Google Developer Knowledge MCP

For any GCP, Firebase, or Cloud Run work:

1. Search: `mcp__google-developer-knowledge__search_documents` with a query
   derived from the issue (e.g., "Cloud Run environment variables configuration")
2. Read: `mcp__google-developer-knowledge__get_documents` for the specific doc
3. Search before implementing — GCP APIs change frequently and your training
   data may be outdated

### ADK MCP + Skills

For any Agent Development Kit work:

1. Load `/adk-dev-guide` at the start of the session — it has mandatory
   development guidelines
2. Load `/adk-cheatsheet` before writing agent code — API quick reference
3. For specific API questions: `mcp__adk-docs__list_doc_sources` first to see
   what's available, then `mcp__adk-docs__fetch_docs` for the relevant page
4. For new agent projects: `/adk-scaffold`
5. For deployment: `/adk-deploy-guide`
6. For evaluation: `/adk-eval-guide`
7. For observability: `/adk-observability-guide`

### Context7 MCP

For any third-party library or package:

1. Resolve: `resolve-library-id` with the library name to get the Context7 ID
2. Query: `query-docs` with the resolved ID and your specific question
3. Use this for API syntax, configuration options, migration guides, and
   version-specific behavior

### Frontend Design Skill

For creating or modifying UI components:

1. Invoke `/frontend-design` — it provides design principles, component
   patterns, and aesthetic guidelines
2. Use it when the issue involves creating new pages, components, or visual
   elements — not for backend API changes that happen to serve a frontend

### Playwright CLI Skill

For verifying visual changes:

1. Invoke `/playwright-cli` after implementation to take screenshots and
   verify the UI looks correct
2. Use it when the issue involves layout changes, styling updates, or any
   visual modifications that should be verified programmatically

## Rules

- **Ground before implementing**: Always load relevant docs before writing code.
  Don't write code based on what you think the API looks like — verify first.
- **Multiple domains**: Issues often span domains (e.g., an ADK agent that
  deploys to Cloud Run). Use ALL relevant grounding sources, starting with the
  most foundational.
- **Unavailable sources**: If a grounding source isn't available in your session
  (MCP not configured, skill not installed), proceed with caution. Note the
  gap in your PR description so the review agent knows which docs weren't
  consulted.
- **Don't over-ground**: If the issue is a simple Python refactor with no
  external dependencies, you don't need to query any MCP. Use judgment.
