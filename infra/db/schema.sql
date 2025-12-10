-- TROUPE OS — MASTER POSTGRESQL SCHEMA (PHASE 0)
-- Authoritative data backbone for Troupe OS

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- CREATE EXTENSION IF NOT EXISTS "vector";  -- disabled: not available on Railway managed Postgres

-- =========================
-- USERS & IDENTITY
-- =========================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE,
    password_hash TEXT,
    display_name TEXT,
    is_ai BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE organization_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (organization_id, user_id)
);

-- =========================
-- ROLES & PERMISSIONS
-- =========================

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE role_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (role_id, permission_id)
);

CREATE TABLE user_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, role_id)
);

-- =========================
-- ASSETS
-- =========================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'asset_type') THEN
        CREATE TYPE asset_type AS ENUM ('music','art','collectible','nft','document','other');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'asset_status') THEN
        CREATE TYPE asset_status AS ENUM ('draft','indexed','published','on_sale','sold','archived');
    END IF;
END$$;

CREATE TABLE assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type asset_type NOT NULL,
    status asset_status DEFAULT 'draft',
    title TEXT,
    owner_id UUID REFERENCES users(id),
    organization_id UUID REFERENCES organizations(id),
    source TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    CHECK (num_nonnulls(owner_id, organization_id) = 1)
);

CREATE TABLE asset_tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (asset_id, tag)
);

-- NOTE: embedding stored as a float array instead of pgvector::vector(1536)
-- This keeps the data model but drops native vector indexing for now.
CREATE TABLE asset_embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    embedding double precision[], -- was VECTOR(1536)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =========================
-- FINANCIAL SYSTEM (DOUBLE ENTRY LEDGER)
-- =========================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transaction_status') THEN
        CREATE TYPE transaction_status AS ENUM ('pending','confirmed','failed','reversed');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transaction_type') THEN
        CREATE TYPE transaction_type AS ENUM ('fiat','crypto');
    END IF;
END$$;

CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_user_id UUID REFERENCES users(id),
    owner_org_id UUID REFERENCES organizations(id),
    currency_code TEXT, -- e.g. USD, USDC, ETH
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    CHECK (owner_user_id IS NOT NULL OR owner_org_id IS NOT NULL)
);

-- Core double-entry ledger: every business event must produce at least two entries
CREATE TABLE ledger_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID REFERENCES transactions(id),
    account_id UUID NOT NULL REFERENCES accounts(id),
    amount NUMERIC(20,8) NOT NULL CHECK (amount > 0), -- always positive; use is_debit to indicate direction
    is_debit BOOLEAN NOT NULL,
    reference TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type transaction_type,
    status transaction_status DEFAULT 'pending',
    from_account UUID REFERENCES accounts(id),
    to_account UUID REFERENCES accounts(id),
    amount NUMERIC(20,8),
    currency_code TEXT,
    external_reference TEXT, -- processor tx id, tx hash, etc.
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =========================
-- MARKETPLACE
-- =========================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
        CREATE TYPE order_status AS ENUM ('draft','pending','paid','fulfilled','cancelled','refunded');
    END IF;
END$$;

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(id),
    organization_id UUID REFERENCES organizations(id),
    sku TEXT,
    title TEXT,
    description TEXT,
    currency_code TEXT,
    price NUMERIC(20,8),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    organization_id UUID REFERENCES organizations(id),
    status order_status DEFAULT 'draft',
    currency_code TEXT,
    subtotal NUMERIC(20,8),
    total NUMERIC(20,8),
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (user_id IS NOT NULL OR organization_id IS NOT NULL)
);

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id),
    asset_id UUID REFERENCES assets(id),
    quantity INT NOT NULL DEFAULT 1,
    unit_price NUMERIC(20,8),
    total_price NUMERIC(20,8),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (product_id IS NOT NULL OR asset_id IS NOT NULL)
);

-- =========================
-- AI WORKFORCE
-- =========================

CREATE TABLE ai_departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ai_agents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id), -- backing identity (if any)
    department_id UUID REFERENCES ai_departments(id),
    role TEXT,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ai_task_status') THEN
        CREATE TYPE ai_task_status AS ENUM ('queued','in_progress','completed','failed','cancelled');
    END IF;
END$$;

CREATE TABLE ai_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id UUID REFERENCES ai_agents(id) ON DELETE SET NULL,
    task_type TEXT,
    status ai_task_status DEFAULT 'queued',
    input_payload JSONB,
    output_payload JSONB,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- =========================
-- SECURITY & AUDIT
-- =========================

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID REFERENCES users(id),
    actor_is_ai BOOLEAN DEFAULT FALSE,
    action TEXT NOT NULL,
    target_type TEXT,
    target_id UUID,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =========================
-- SYSTEM JOBS & EVENTS
-- =========================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_status') THEN
        CREATE TYPE job_status AS ENUM ('queued','in_progress','completed','failed','cancelled');
    END IF;
END$$;

CREATE TABLE system_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_type TEXT NOT NULL,
    status job_status DEFAULT 'queued',
    priority INT DEFAULT 0,
    payload JSONB,
    last_error TEXT,
    run_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE TABLE system_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type TEXT NOT NULL,
    actor_id UUID REFERENCES users(id),
    payload JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =========================
-- INDEXES
-- =========================

-- Users & orgs
CREATE INDEX IF NOT EXISTS idx_org_members_org ON organization_members (organization_id);
CREATE INDEX IF NOT EXISTS idx_org_members_user ON organization_members (user_id);

-- Roles & permissions
CREATE INDEX IF NOT EXISTS idx_role_permissions_role ON role_permissions (role_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_permission ON role_permissions (permission_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_user ON user_roles (user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON user_roles (role_id);

-- Assets
CREATE INDEX IF NOT EXISTS idx_assets_owner ON assets (owner_id);
CREATE INDEX IF NOT EXISTS idx_assets_org ON assets (organization_id);
CREATE INDEX IF NOT EXISTS idx_assets_type_status ON assets (type, status);
CREATE INDEX IF NOT EXISTS idx_asset_tags_asset ON asset_tags (asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_tags_tag ON asset_tags (tag);
CREATE INDEX IF NOT EXISTS idx_asset_embeddings_asset ON asset_embeddings (asset_id);

-- Financial
CREATE INDEX IF NOT EXISTS idx_accounts_owner_user ON accounts (owner_user_id);
CREATE INDEX IF NOT EXISTS idx_accounts_owner_org ON accounts (owner_org_id);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_account ON ledger_entries (account_id);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_tx ON ledger_entries (transaction_id);
CREATE INDEX IF NOT EXISTS idx_transactions_status_type ON transactions (status, type);
CREATE INDEX IF NOT EXISTS idx_transactions_accounts ON transactions (from_account, to_account);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions (created_at);

-- Marketplace
CREATE INDEX IF NOT EXISTS idx_products_asset ON products (asset_id);
CREATE INDEX IF NOT EXISTS idx_products_org ON products (organization_id);
CREATE INDEX IF NOT EXISTS idx_products_active ON products (is_active);
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_org ON orders (organization_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders (created_at);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items (order_id);

-- AI workforce
CREATE INDEX IF NOT EXISTS idx_ai_agents_dept ON ai_agents (department_id);
CREATE INDEX IF NOT EXISTS idx_ai_agents_user ON ai_agents (user_id);
CREATE INDEX IF NOT EXISTS idx_ai_agents_active ON ai_agents (is_active);
CREATE INDEX IF NOT EXISTS idx_ai_tasks_agent ON ai_tasks (agent_id);
CREATE INDEX IF NOT EXISTS idx_ai_tasks_status ON ai_tasks (status);
CREATE INDEX IF NOT EXISTS idx_ai_tasks_created_at ON ai_tasks (created_at);

-- Security & jobs
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs (actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs (created_at);
CREATE INDEX IF NOT EXISTS idx_system_jobs_status ON system_jobs (status);
CREATE INDEX IF NOT EXISTS idx_system_jobs_run_at ON system_jobs (run_at);
CREATE INDEX IF NOT EXISTS idx_system_events_type ON system_events (event_type);
CREATE INDEX IF NOT EXISTS idx_system_events_created_at ON system_events (created_at);
