-- TROUPE OS — MASTER POSTGRESQL SCHEMA
-- Phase 0 Foundation Lock
-- This schema is the authoritative data backbone for Troupe OS

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";
CREATE EXTENSION IF NOT EXISTS "vector";

SET timezone TO 'UTC';

-- Utility: auto-manage updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc', now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =========================
-- ENUMERATIONS
-- =========================

CREATE TYPE user_kind AS ENUM ('human', 'ai_agent');
CREATE TYPE asset_type AS ENUM ('music', 'art', 'collectible', 'nft', 'document', 'other');
CREATE TYPE asset_status AS ENUM ('draft', 'indexed', 'published', 'on_sale', 'sold', 'archived');
CREATE TYPE asset_visibility AS ENUM ('public', 'internal', 'private');
CREATE TYPE account_type AS ENUM ('asset', 'liability', 'equity', 'revenue', 'expense');
CREATE TYPE account_status AS ENUM ('open', 'suspended', 'closed');
CREATE TYPE transaction_type AS ENUM ('fiat', 'crypto');
CREATE TYPE transaction_status AS ENUM ('pending', 'confirmed', 'failed', 'reversed');
CREATE TYPE listing_status AS ENUM ('draft', 'active', 'paused', 'ended');
CREATE TYPE order_status AS ENUM ('cart', 'pending_payment', 'paid', 'fulfilled', 'cancelled', 'refunded');
CREATE TYPE fulfillment_status AS ENUM ('pending', 'in_progress', 'fulfilled', 'failed');
CREATE TYPE ai_task_status AS ENUM ('queued', 'in_progress', 'completed', 'failed', 'cancelled');
CREATE TYPE job_status AS ENUM ('queued', 'running', 'succeeded', 'failed', 'cancelled');
CREATE TYPE ledger_txn_status AS ENUM ('draft', 'posted', 'void');
CREATE TYPE ledger_entry_direction AS ENUM ('debit', 'credit');
CREATE TYPE audit_actor_type AS ENUM ('user', 'ai_agent', 'system');

-- =========================
-- USERS & IDENTITY
-- =========================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    kind user_kind NOT NULL DEFAULT 'human',
    email CITEXT UNIQUE NOT NULL,
    password_hash TEXT,
    display_name TEXT,
    handle CITEXT UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ
);
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TYPE identity_provider AS ENUM ('password', 'oauth_google', 'oauth_github', 'wallet');
CREATE TABLE user_identities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id),
    provider identity_provider NOT NULL,
    provider_user_id TEXT NOT NULL,
    wallet_address TEXT,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    UNIQUE (provider, provider_user_id),
    identity_key TEXT GENERATED ALWAYS AS (CASE WHEN provider = 'wallet' THEN wallet_address ELSE provider_user_id END) STORED NOT NULL,
    UNIQUE (user_id, provider, identity_key),
    CHECK ((provider = 'wallet' AND wallet_address IS NOT NULL) OR provider <> 'wallet'),
    CHECK ((provider <> 'wallet' AND provider_user_id IS NOT NULL) OR provider = 'wallet')
);
CREATE TRIGGER trg_user_identities_updated_at BEFORE UPDATE ON user_identities FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_user_identities_user ON user_identities(user_id);
CREATE INDEX idx_user_identities_wallet ON user_identities(wallet_address);

CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    slug CITEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ
);
CREATE TRIGGER trg_organizations_updated_at BEFORE UPDATE ON organizations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE organization_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invited_by UUID REFERENCES users(id),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE (organization_id, user_id)
);
CREATE TRIGGER trg_org_members_updated_at BEFORE UPDATE ON organization_members FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_org_members_org ON organization_members(organization_id);
CREATE INDEX idx_org_members_user ON organization_members(user_id);

-- =========================
-- ROLES & PERMISSIONS (RBAC)
-- =========================

CREATE TYPE role_scope AS ENUM ('system', 'organization');

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    scope role_scope NOT NULL DEFAULT 'system',
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE (name, scope, organization_id),
    CHECK ((scope = 'system' AND organization_id IS NULL) OR (scope = 'organization' AND organization_id IS NOT NULL))
);
CREATE TRIGGER trg_roles_updated_at BEFORE UPDATE ON roles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_roles_org ON roles(organization_id);
CREATE INDEX idx_roles_scope ON roles(scope);
CREATE UNIQUE INDEX idx_roles_system_unique ON roles(name) WHERE scope = 'system';
CREATE UNIQUE INDEX idx_roles_org_unique ON roles(organization_id, name) WHERE scope = 'organization';

CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE TRIGGER trg_permissions_updated_at BEFORE UPDATE ON permissions FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE role_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    UNIQUE (role_id, permission_id)
);
CREATE INDEX idx_role_permissions_role ON role_permissions(role_id);
CREATE INDEX idx_role_permissions_permission ON role_permissions(permission_id);

CREATE TABLE user_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    UNIQUE (user_id, role_id, organization_id)
);
CREATE INDEX idx_user_roles_user ON user_roles(user_id);
CREATE INDEX idx_user_roles_role ON user_roles(role_id);
CREATE INDEX idx_user_roles_org ON user_roles(organization_id);

-- =========================
-- ASSETS, METADATA, TAGS, EMBEDDINGS
-- =========================

CREATE TABLE assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    owner_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    type asset_type NOT NULL,
    status asset_status NOT NULL DEFAULT 'draft',
    title TEXT NOT NULL,
    description TEXT,
    source TEXT,
    storage_uri TEXT,
    checksum TEXT,
    metadata JSONB,
    visibility asset_visibility NOT NULL DEFAULT 'private',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ
);
CREATE TRIGGER trg_assets_updated_at BEFORE UPDATE ON assets FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_assets_org ON assets(organization_id);
CREATE INDEX idx_assets_owner ON assets(owner_user_id);
CREATE INDEX idx_assets_type_status ON assets(type, status);
CREATE INDEX idx_assets_metadata ON assets USING GIN (metadata);
COMMENT ON COLUMN assets.metadata IS 'Structured asset metadata (traits, links, provenance); validated by service layer per asset type.';

CREATE TABLE asset_attributes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    UNIQUE (asset_id, key, value)
);
CREATE INDEX idx_asset_attributes_asset ON asset_attributes(asset_id);

CREATE TABLE asset_tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    UNIQUE (asset_id, tag)
);
CREATE INDEX idx_asset_tags_asset ON asset_tags(asset_id);
CREATE INDEX idx_asset_tags_tag ON asset_tags(tag);

CREATE TABLE asset_embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    embedding vector NOT NULL,
    dimension INTEGER GENERATED ALWAYS AS (vector_dims(embedding)) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX idx_asset_embeddings_asset ON asset_embeddings(asset_id);
CREATE INDEX idx_asset_embeddings_vector ON asset_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
COMMENT ON COLUMN asset_embeddings.dimension IS 'Derived dimensionality for validating provider embeddings and enforcing consistent vector sizes.';
COMMENT ON INDEX idx_asset_embeddings_vector IS 'IVFFlat cosine index using ~100 lists (roughly sqrt(N)); tune lists per dataset size for recall/performance balance.';

-- =========================
-- ORGANIZATIONS / GROUPS
-- =========================

CREATE TABLE groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE (organization_id, name)
);
CREATE TRIGGER trg_groups_updated_at BEFORE UPDATE ON groups FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_groups_org ON groups(organization_id);

CREATE TABLE group_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    UNIQUE (group_id, user_id)
);
CREATE INDEX idx_group_members_group ON group_members(group_id);
CREATE INDEX idx_group_members_user ON group_members(user_id);

-- =========================
-- FINANCIAL ACCOUNTS & DOUBLE-ENTRY LEDGER
-- =========================

CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    owner_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    type account_type NOT NULL,
    status account_status NOT NULL DEFAULT 'open',
    currency CHAR(3) NOT NULL,
    parent_account_id UUID REFERENCES accounts(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ
);
CREATE TRIGGER trg_accounts_updated_at BEFORE UPDATE ON accounts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_accounts_org ON accounts(organization_id);
CREATE INDEX idx_accounts_owner ON accounts(owner_user_id);
CREATE INDEX idx_accounts_parent ON accounts(parent_account_id);
CREATE INDEX idx_accounts_type ON accounts(type);
CREATE UNIQUE INDEX idx_accounts_org_code ON accounts(organization_id, code) WHERE organization_id IS NOT NULL;
CREATE UNIQUE INDEX idx_accounts_system_code ON accounts(code) WHERE organization_id IS NULL;

CREATE TABLE ledger_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    status ledger_txn_status NOT NULL DEFAULT 'draft',
    reference_type TEXT,
    reference_id UUID,
    memo TEXT,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE TRIGGER trg_ledger_transactions_updated_at BEFORE UPDATE ON ledger_transactions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_ledger_txns_org ON ledger_transactions(organization_id);
CREATE INDEX idx_ledger_txns_status ON ledger_transactions(status);

CREATE TABLE ledger_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ledger_transaction_id UUID NOT NULL REFERENCES ledger_transactions(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounts(id),
    direction ledger_entry_direction NOT NULL,
    amount NUMERIC(32, 8) NOT NULL CHECK (amount > 0),
    currency CHAR(3) NOT NULL,
    asset_id UUID REFERENCES assets(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX idx_ledger_entries_txn ON ledger_entries(ledger_transaction_id);
CREATE INDEX idx_ledger_entries_account ON ledger_entries(account_id);
CREATE INDEX idx_ledger_entries_asset ON ledger_entries(asset_id);

CREATE OR REPLACE FUNCTION assert_ledger_balance(txn_id UUID, txn_status ledger_txn_status)
RETURNS VOID AS $$
DECLARE
    txn_balance NUMERIC(32, 8);
BEGIN
    IF txn_status = 'posted' THEN
        SELECT COALESCE(SUM(CASE WHEN direction = 'debit' THEN amount ELSE -amount END), 0)
        INTO txn_balance
        FROM ledger_entries
        WHERE ledger_transaction_id = txn_id;

        IF txn_balance <> 0 THEN
            RAISE EXCEPTION 'Ledger transaction % is not balanced (%).', txn_id, txn_balance;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_balance_from_entries()
RETURNS TRIGGER AS $$
DECLARE
    txn_id UUID := COALESCE(NEW.ledger_transaction_id, OLD.ledger_transaction_id);
    txn_status ledger_txn_status;
BEGIN
    SELECT status INTO txn_status FROM ledger_transactions WHERE id = txn_id;
    IF txn_status = 'posted' THEN
        PERFORM assert_ledger_balance(txn_id, txn_status);
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_balance_from_transactions()
RETURNS TRIGGER AS $$
DECLARE
    txn_id UUID := COALESCE(NEW.id, OLD.id);
    txn_status ledger_txn_status := COALESCE(NEW.status, OLD.status);
BEGIN
    IF txn_status = 'posted' THEN
        PERFORM assert_ledger_balance(txn_id, txn_status);
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_ledger_entries_balanced
AFTER INSERT OR UPDATE OR DELETE ON ledger_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_balance_from_entries();

CREATE CONSTRAINT TRIGGER trg_ledger_transactions_balanced
AFTER INSERT OR UPDATE ON ledger_transactions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_balance_from_transactions();

-- =========================
-- TRANSACTIONS (FIAT + CRYPTO)
-- =========================

CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    address TEXT NOT NULL,
    chain TEXT,
    network TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ,
    UNIQUE (address, chain, network)
);
CREATE TRIGGER trg_wallets_updated_at BEFORE UPDATE ON wallets FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_wallets_user ON wallets(user_id);
CREATE INDEX idx_wallets_org ON wallets(organization_id);

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type transaction_type NOT NULL,
    status transaction_status NOT NULL DEFAULT 'pending',
    from_account_id UUID REFERENCES accounts(id),
    to_account_id UUID REFERENCES accounts(id),
    ledger_transaction_id UUID REFERENCES ledger_transactions(id) ON DELETE SET NULL,
    wallet_id UUID REFERENCES wallets(id),
    amount NUMERIC(32, 8) NOT NULL CHECK (amount > 0),
    currency CHAR(3) NOT NULL,
    tx_hash TEXT,
    payment_processor TEXT,
    external_reference TEXT,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE TRIGGER trg_transactions_updated_at BEFORE UPDATE ON transactions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_transactions_from_account ON transactions(from_account_id);
CREATE INDEX idx_transactions_to_account ON transactions(to_account_id);
CREATE INDEX idx_transactions_wallet ON transactions(wallet_id);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_tx_hash ON transactions(tx_hash);

-- =========================
-- MARKETPLACES (PRODUCTS, LISTINGS, ORDERS, FULFILLMENT)
-- =========================

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    asset_id UUID REFERENCES assets(id) ON DELETE SET NULL,
    sku TEXT,
    base_price NUMERIC(32, 8),
    currency CHAR(3) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ
);
CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_products_org ON products(organization_id);
CREATE INDEX idx_products_asset ON products(asset_id);
CREATE INDEX idx_products_active ON products(is_active);

CREATE TABLE listings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    price NUMERIC(32, 8) NOT NULL,
    currency CHAR(3) NOT NULL,
    status listing_status NOT NULL DEFAULT 'draft',
    inventory_count INTEGER DEFAULT 0,
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ
);
CREATE TRIGGER trg_listings_updated_at BEFORE UPDATE ON listings FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_listings_product ON listings(product_id);
CREATE INDEX idx_listings_status ON listings(status);
CREATE INDEX idx_listings_channel ON listings(channel);

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    buyer_id UUID REFERENCES users(id) ON DELETE SET NULL,
    status order_status NOT NULL DEFAULT 'cart',
    currency CHAR(3) NOT NULL,
    subtotal NUMERIC(32, 8) NOT NULL DEFAULT 0,
    tax_total NUMERIC(32, 8) NOT NULL DEFAULT 0,
    fee_total NUMERIC(32, 8) NOT NULL DEFAULT 0,
    discount_total NUMERIC(32, 8) NOT NULL DEFAULT 0,
    total_amount NUMERIC(32, 8) NOT NULL DEFAULT 0,
    transaction_id UUID REFERENCES transactions(id),
    shipping_address JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ
);
CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_orders_org ON orders(organization_id);
CREATE INDEX idx_orders_buyer ON orders(buyer_id);
CREATE INDEX idx_orders_status ON orders(status);
COMMENT ON COLUMN orders.shipping_address IS 'Shipping address payload (name, line1, line2, city, region, postal_code, country_code, phone) stored as JSON.';

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    listing_id UUID REFERENCES listings(id),
    product_id UUID NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price NUMERIC(32, 8) NOT NULL,
    currency CHAR(3) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_order_items_listing ON order_items(listing_id);
CREATE INDEX idx_order_items_product ON order_items(product_id);

CREATE TABLE fulfillments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    fulfillment_type TEXT NOT NULL,
    status fulfillment_status NOT NULL DEFAULT 'pending',
    tracking_number TEXT,
    fulfilled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE TRIGGER trg_fulfillments_updated_at BEFORE UPDATE ON fulfillments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_fulfillments_order ON fulfillments(order_id);
CREATE INDEX idx_fulfillments_status ON fulfillments(status);

-- =========================
-- AI WORKFORCE (AGENTS, DEPARTMENTS, TASKS, ACTIVITY)
-- =========================

CREATE TABLE ai_departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE TRIGGER trg_ai_departments_updated_at BEFORE UPDATE ON ai_departments FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE ai_agents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    department_id UUID REFERENCES ai_departments(id) ON DELETE SET NULL,
    handle CITEXT UNIQUE,
    role TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    deleted_at TIMESTAMPTZ
);
CREATE TRIGGER trg_ai_agents_updated_at BEFORE UPDATE ON ai_agents FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_ai_agents_user ON ai_agents(user_id);
CREATE INDEX idx_ai_agents_department ON ai_agents(department_id);

CREATE TABLE ai_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id UUID REFERENCES ai_agents(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id),
    task_type TEXT NOT NULL,
    status ai_task_status NOT NULL DEFAULT 'queued',
    priority INTEGER NOT NULL DEFAULT 0,
    payload JSONB,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE TRIGGER trg_ai_tasks_updated_at BEFORE UPDATE ON ai_tasks FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_ai_tasks_agent ON ai_tasks(agent_id);
CREATE INDEX idx_ai_tasks_status ON ai_tasks(status);
CREATE INDEX idx_ai_tasks_type ON ai_tasks(task_type);

CREATE TABLE agent_activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id UUID NOT NULL REFERENCES ai_agents(id) ON DELETE CASCADE,
    task_id UUID REFERENCES ai_tasks(id) ON DELETE SET NULL,
    message TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX idx_agent_activity_agent ON agent_activity_logs(agent_id);
CREATE INDEX idx_agent_activity_task ON agent_activity_logs(task_id);

-- =========================
-- SECURITY & AUDIT LOGS
-- =========================

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_type audit_actor_type NOT NULL,
    actor_id UUID,
    action TEXT NOT NULL,
    target_type TEXT,
    target_id UUID,
    ip_address INET,
    user_agent TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX idx_audit_logs_actor ON audit_logs(actor_id);
CREATE INDEX idx_audit_logs_target ON audit_logs(target_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);

-- =========================
-- SYSTEM EVENTS & AUTOMATION JOBS
-- =========================

CREATE TABLE system_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type TEXT NOT NULL,
    actor_id UUID REFERENCES users(id),
    payload JSONB,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX idx_system_events_type ON system_events(event_type);
CREATE INDEX idx_system_events_actor ON system_events(actor_id);

CREATE TABLE automation_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_type TEXT NOT NULL,
    status job_status NOT NULL DEFAULT 'queued',
    scheduled_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    retry_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);
CREATE TRIGGER trg_automation_jobs_updated_at BEFORE UPDATE ON automation_jobs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE INDEX idx_automation_jobs_status ON automation_jobs(status);
CREATE INDEX idx_automation_jobs_type ON automation_jobs(job_type);
CREATE INDEX idx_automation_jobs_schedule ON automation_jobs(scheduled_at);
