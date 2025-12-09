# TROUPE OS — MASTER SYSTEM SPECIFICATION

## 0. Purpose

Troupe OS is the unified operating system for Troupe Inc.  
It orchestrates:

- Creative IP: music, art, collectibles, NFTs.
- Financial systems: cash, crypto, tokens, revenue streams.
- Marketplaces: digital and physical asset sales, listings, and fulfillment.
- AI workforce: AI employees, agents, and automations.
- Security, analytics, and governance: access control, logs, and system health.

This document is the canonical contract for how the OS is structured and how subsystems fit together.

---

## 1. Core Principles

1. **Single Source of Truth**
   - All critical entities (users, assets, transactions, agents) exist in a normalized, queryable schema.
   - No shadow databases for core records.

2. **Modular, Composable Design**
   - Features are grouped into modules (music, art, collectibles, crypto, HR/AI, admin).
   - Each module exposes clear APIs and UI surfaces.

3. **Security-First**
   - Principle of least privilege for every role and service.
   - All sensitive operations require auth + role checks + logging.
   - Every write operation is auditable.

4. **AI-First Automation**
   - All major workflows (ingestion, indexing, pricing, routing, notifications) are designed to be AI-operated or AI-assisted.
   - Human intervention is supervisory, not manual execution for routine tasks.

5. **Revenue as a Core Metric**
   - Every module must be traceable to current or potential revenue.
   - All data pipelines are designed to support monetization, analytics, and experimentation.

6. **Built Once, Extended Forever**
   - Initial versions are production-grade, not prototypes.
   - Upgrades are additive and backward-compatible whenever possible.

---

## 2. High-Level Architecture

### 2.1 Platform Layers

1. **Interface Layer**
   - Web apps (Next.js) for:
     - Public hub (site, gallery, marketplace front).
     - Console / Admin panels.
     - Specialized dashboards (HR/AI, security, finance, assets).

2. **Service Layer**
   - API gateway for public and internal services.
   - Microservices or service modules for:
     - Auth & identity.
     - Asset registry and indexing.
     - Financial ledger and payments.
     - Marketplace operations.
     - AI worker orchestration.
     - Notification and event routing.

3. **Data Layer**
   - Primary: PostgreSQL (relational).
   - Secondary: vector database for embeddings and semantic search.
   - Object storage for media, documents, and large assets.

4. **Automation Layer**
   - AI agents (internal “employees”).
   - Job queues and schedulers.
   - Rule engines for triggers, alerts, and workflows.

5. **Security & Governance Layer**
   - RBAC (role-based access control).
   - Policy enforcement (per module and per endpoint).
   - Audit logs.
   - Incident reporting and security dashboards.

---

## 3. Core Domains

### 3.1 Users & Identity

- **Entities**
  - Users (humans).
  - AI agents / employees.
  - Organizations / groups.
  - Permissions, roles, and access scopes.

- **Requirements**
  - Support standard auth (email/password, OAuth) plus wallet-based auth for crypto features.
  - Support role hierarchies (Owner, Admin, Editor, Viewer, Guest).
  - Associate every action with an actor (user or agent) and a timestamp.

---

### 3.2 Assets

“Asset” is a first-class concept. Assets can be:

- Music tracks, albums, stems.
- Art pieces (digital or tokenized).
- Collectible items (physical cards, graded slabs, digital collectibles).
- NFTs or other on-chain items.
- Documents and media related to projects.

**Key Properties (conceptual):**

- `id` (global unique identifier).
- `type` (music, art, collectible, nft, doc, other).
- `source` (uploaded, imported, scraped, on-chain reference).
- `owner` (user, group, or Troupe Inc.).
- `status` (draft, indexed, published, archived, on-sale, sold).
- `metadata` (structured description, tags, traits).
- `links` (storage locations, on-chain links, marketplace listings).

**Processes:**

1. **Ingestion**
   - Uploads from UI.
   - Imports from folders, archives, or external systems.
   - On-chain scans (for NFTs / tokens) when applicable.

2. **Indexing**
   - Generate fingerprints, embeddings, tags, categories.
   - Link to existing projects, campaigns, or collections.

3. **Publication**
   - Expose assets in galleries, playlists, collections, or product pages.

4. **Lifecycle**
   - Track changes, price history, ownership history, and performance metrics.

---

### 3.3 Financial Systems

The OS must support:

- Traditional revenue (sales, services, royalties).
- Crypto flows (wallet balances, swaps, liquidity positions, NFT sales).
- Internal tokens or credits (if/when introduced).

**Key Concepts:**

- **Ledger**
  - Double-entry style tracking for all inflows and outflows.
  - Entries linked to assets, orders, campaigns, or projects where possible.

- **Accounts**
  - Accounts for:
    - Troupe Inc. (global).
    - Sub-brands (music, art, collectibles, crypto, cannabis, etc.).
    - Individual users or collaborators.

- **Transactions**
  - Fiat and crypto.
  - Status states (pending, confirmed, failed, reversed).
  - Source and destination (e.g., wallet A → wallet B, card processor → bank).

- **Reporting**
  - P&L views per brand, per asset type, per campaign.
  - Cashflow timeline.
  - Unrealized vs realized gains for crypto and collectibles.

---

### 3.4 Marketplaces & Commerce

The OS needs to power:

- Primary sales (direct listing and selling).
- Secondary markets (resale when applicable).
- Bundles and drops (curated sets of assets).
- Auctions or time-bound events (future expansion).

**Commerce Entities:**

- Products (an asset or bundle with a price and configuration).
- Listings (a product offered on a channel).
- Orders (a user’s purchase intent and completion).
- Fulfillment (digital delivery, physical shipping).
- Fees and royalties.

**Channels:**

- Direct TroupeInc.com storefronts.
- Embedded widgets on partner/white-label pages (future).
- On-chain marketplaces (if integrated).

---

### 3.5 AI Workforce (Agents / Employees)

AI workers are treated as:

- First-class entities with:
  - Name, role, description.
  - Permissions and scopes.
  - Assigned tasks and outputs.
  - Performance metrics.

**Functions:**

- Indexing assets.
- Generating metadata, descriptions, and marketing copy.
- Monitoring markets and flagging opportunities (collectibles, crypto).
- Running analysis for financials, campaigns, and operations.
- Responding to internal prompts (support, research, planning).

**Governance:**

- Every agent belongs to one or more “departments” (e.g., Finance, Security, Creative).
- Permission sets limit what an agent can view, modify, or trigger.
- Activity logs record all automated decisions and changes.

---

### 3.6 Security & Governance

Security objectives:

- Control who can see and do what across all modules.
- Make every change traceable.
- Surface incidents and anomalies quickly.

**Components:**

- Role and permission definitions.
- Policy engine (e.g., “only Owner or Finance Admin can view full ledger details”).
- Logging for:
  - Auth events.
  - Data writes.
  - Configuration changes.
- Dashboards:
  - Security overview.
  - Recent incidents.
  - Access review reports.

---

## 4. Module Map

The OS is organized into modules that can be mapped to apps and packages in the repo.

1. **Core**
   - Shared types, utilities, and configuration.
   - Base API handlers and middleware.

2. **Users & Auth**
   - Identity management.
   - Session handling and token issuance.
   - Wallet connections (where applicable).

3. **Assets**
   - Asset CRUD.
   - Ingestion and indexing jobs.
   - Search and filter APIs.

4. **Financials**
   - Ledger and account models.
   - Transaction ingestion (manual and automated).
   - Reporting endpoints.

5. **Marketplace**
   - Product configuration.
   - Listings, carts, checkout, orders, and fulfillment.
   - Pricing and discount logic.

6. **AI Workforce**
   - Agent registry and roles.
   - Task queues and orchestration.
   - Agent performance tracking.

7. **Security & Governance**
   - RBAC definitions and middleware.
   - Policy rules.
   - Audit logs and security reporting.

8. **Admin Console**
   - Internal dashboards for:
     - Assets.
     - Financials.
     - AI workforce.
     - Security.
   - Tools for configuration and operational oversight.

9. **Public Hub**
   - Front-facing site for:
     - Music (ZIG ZAG).
     - Art galleries.
     - Collectibles and marketplaces.
     - Brand storytelling and funnels.

---

## 5. Environments & Deployment

### 5.1 Environments

- **Development**
  - Fast iteration.
  - Lower security constraints, but still with RBAC active.

- **Staging**
  - Mirrors production structure.
  - Used for testing new features end-to-end.

- **Production**
  - Live site and services.
  - Strict security and monitoring.

### 5.2 CI/CD Expectations

- Automated tests on every push to main branches.
- Linting and type checks (even if codebase is JS-first, type-checking tools are encouraged).
- Deployment gates for production (manual approval or protected branches).
- Rollback strategy with previous deployment snapshots.

---

## 6. Data & Observability

- **Metrics**
  - Traffic, latency, error rates.
  - Revenue metrics by module and channel.
  - AI agent activity and performance.

- **Logs**
  - Structured logs for all critical services.
  - Correlation IDs across requests and jobs.

- **Tracing**
  - Trace major flows: ingestion → indexing → listing → sale → ledger.

- **Backups**
  - Regular backups for databases and critical data.
  - Documented restore procedures.

---

## 7. Roadmap Phases (High Level)

1. **Phase 0 — Foundation**
   - Lock spec (this document).
   - Define initial database schema.
   - Establish core API gateway and auth.

2. **Phase 1 — Asset + User Core**
   - Implement user/auth module.
   - Implement asset registry and ingestion basics.
   - Minimal admin console for inspection.

3. **Phase 2 — Financials + Marketplace Base**
   - Implement ledger and accounts.
   - Implement basic product/listing/order models.
   - Simple sales pipeline on the public hub.

4. **Phase 3 — AI Workforce Integration**
   - Register AI agents as first-class entities.
   - Automate ingestion, indexing, and reporting workflows.

5. **Phase 4 — Security, Governance, and Advanced Dashboards**
   - Security dashboard and incident views.
   - Governance frameworks and reviews.
   - Advanced analytics and experimentation tools.

6. **Phase 5 — Expansion & External Integrations**
   - Third-party marketplaces and services.
   - Additional brands and verticals.

---

## 8. Change Management

- This spec is versioned in Git.
- Any structural changes to domains, modules, or principles:
  - Must be done via pull request.
  - Must include rationale and migration notes.
- This document is the first place to update when the OS design evolves.
