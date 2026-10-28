--
-- PostgreSQL database dump
--

\restrict ViplJYeqRmW4mhkfMtWAEtWyQ0VW7DJ2gUGKuWlvXLabxtJc3xCbDxVm0hE62Vu

-- Dumped from database version 17.10
-- Dumped by pg_dump version 17.10

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.access_tokens (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    account_id text COLLATE pg_catalog."C",
    label text COLLATE pg_catalog."C",
    role text COLLATE pg_catalog."C",
    prefix text COLLATE pg_catalog."C",
    token_hash text COLLATE pg_catalog."C",
    expires_at text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C",
    created_by text COLLATE pg_catalog."C",
    last_used_at text COLLATE pg_catalog."C",
    revoked_at text COLLATE pg_catalog."C"
);


--
-- Name: access_tokens_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.access_tokens ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.access_tokens_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: account_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_identities (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    account_id text COLLATE pg_catalog."C",
    strategy text COLLATE pg_catalog."C",
    issuer text COLLATE pg_catalog."C",
    subject text COLLATE pg_catalog."C",
    email text COLLATE pg_catalog."C",
    linked_at text COLLATE pg_catalog."C",
    last_used_at text COLLATE pg_catalog."C"
);


--
-- Name: account_identities_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.account_identities ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.account_identities_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    name text COLLATE pg_catalog."C",
    display_name text COLLATE pg_catalog."C",
    kind text COLLATE pg_catalog."C",
    role text COLLATE pg_catalog."C",
    email text COLLATE pg_catalog."C",
    status text DEFAULT 'active'::text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C",
    created_by text COLLATE pg_catalog."C",
    invited_at text COLLATE pg_catalog."C"
);


--
-- Name: accounts_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.accounts ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.accounts_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: articles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.articles (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    revision bigint DEFAULT 1,
    name text COLLATE pg_catalog."C",
    sku text COLLATE pg_catalog."C",
    unit text COLLATE pg_catalog."C",
    package_size numeric,
    balance numeric DEFAULT 0,
    movement_revision bigint DEFAULT 0,
    min_level numeric,
    max_level numeric,
    cost_price_ore bigint,
    supplier text COLLATE pg_catalog."C",
    lead_days bigint DEFAULT 0,
    department text COLLATE pg_catalog."C",
    department_revision bigint DEFAULT 1,
    active bigint DEFAULT 1,
    product_id text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C"
);


--
-- Name: articles_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.articles ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.articles_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: assignment_overrides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assignment_overrides (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    assignment_id text COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    employee_id text COLLATE pg_catalog."C",
    reason text COLLATE pg_catalog."C",
    conflict_ids text COLLATE pg_catalog."C",
    conflict_summary text COLLATE pg_catalog."C",
    created_by text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C"
);


--
-- Name: assignment_overrides_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.assignment_overrides ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.assignment_overrides_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assignments (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    employee_id text COLLATE pg_catalog."C",
    auto bigint,
    auto_department text COLLATE pg_catalog."C",
    started_at text COLLATE pg_catalog."C",
    ended_at text COLLATE pg_catalog."C"
);


--
-- Name: assignments_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.assignments ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.assignments_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: attachment_contents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attachment_contents (
    id text NOT NULL COLLATE pg_catalog."C",
    content bytea NOT NULL
);


--
-- Name: attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attachments (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    entity text COLLATE pg_catalog."C",
    record_id text COLLATE pg_catalog."C",
    filename text COLLATE pg_catalog."C",
    content_type text COLLATE pg_catalog."C",
    size bigint,
    width bigint,
    height bigint,
    sha256 text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C",
    created_by text COLLATE pg_catalog."C",
    account text COLLATE pg_catalog."C"
);


--
-- Name: attachments_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.attachments ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.attachments_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    at text COLLATE pg_catalog."C",
    actor text COLLATE pg_catalog."C",
    tool text COLLATE pg_catalog."C",
    outcome text COLLATE pg_catalog."C",
    entity_type text COLLATE pg_catalog."C",
    entity_id text COLLATE pg_catalog."C",
    request_key text COLLATE pg_catalog."C",
    error_code text COLLATE pg_catalog."C",
    request_id text COLLATE pg_catalog."C",
    reason text COLLATE pg_catalog."C",
    credential text COLLATE pg_catalog."C"
);


--
-- Name: audit_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.audit ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.audit_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookings (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    product_id text COLLATE pg_catalog."C",
    quantity bigint,
    from_date text COLLATE pg_catalog."C",
    to_date text COLLATE pg_catalog."C"
);


--
-- Name: bookings_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.bookings ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.bookings_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: catalog_changes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_changes (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    resource_type text COLLATE pg_catalog."C",
    resource_id text COLLATE pg_catalog."C",
    operation text COLLATE pg_catalog."C",
    changed_fields text COLLATE pg_catalog."C",
    at text COLLATE pg_catalog."C",
    by text COLLATE pg_catalog."C",
    product_id text COLLATE pg_catalog."C"
);


--
-- Name: catalog_changes_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.catalog_changes ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.catalog_changes_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: checklist_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checklist_items (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    order_line_id text COLLATE pg_catalog."C",
    origin text DEFAULT 'manual'::text COLLATE pg_catalog."C",
    source_key text COLLATE pg_catalog."C",
    description text COLLATE pg_catalog."C",
    category text COLLATE pg_catalog."C",
    computed_quantity numeric,
    done_quantity numeric,
    done bigint
);


--
-- Name: checklist_items_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.checklist_items ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.checklist_items_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: choice_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.choice_groups (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    revision bigint DEFAULT 1,
    name text COLLATE pg_catalog."C",
    active bigint DEFAULT 1,
    members text COLLATE pg_catalog."C"
);


--
-- Name: choice_groups_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.choice_groups ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.choice_groups_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: confirmation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.confirmation (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    token_hash text COLLATE pg_catalog."C",
    actor text COLLATE pg_catalog."C",
    tool text COLLATE pg_catalog."C",
    input_hash text COLLATE pg_catalog."C",
    expires_at text COLLATE pg_catalog."C",
    request_id text COLLATE pg_catalog."C",
    used_at text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C"
);


--
-- Name: confirmation_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.confirmation ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.confirmation_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: consumption_commands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consumption_commands (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    order_revision bigint,
    effective_date text COLLATE pg_catalog."C",
    fingerprint text COLLATE pg_catalog."C"
);


--
-- Name: consumption_commands_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.consumption_commands ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.consumption_commands_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    marketing_consent bigint,
    consent_source text COLLATE pg_catalog."C",
    consent_at text COLLATE pg_catalog."C",
    erased bigint,
    erased_at text COLLATE pg_catalog."C",
    revision bigint DEFAULT 1,
    name text COLLATE pg_catalog."C",
    email text COLLATE pg_catalog."C",
    phone text COLLATE pg_catalog."C",
    notes text COLLATE pg_catalog."C",
    completed_orders bigint DEFAULT 0,
    created_at text COLLATE pg_catalog."C"
);


--
-- Name: customers_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.customers ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.customers_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employees (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    name text COLLATE pg_catalog."C",
    actor text COLLATE pg_catalog."C",
    role text COLLATE pg_catalog."C",
    department text COLLATE pg_catalog."C",
    auto_assign_in_department bigint,
    active bigint DEFAULT 1,
    created_at text COLLATE pg_catalog."C"
);


--
-- Name: employees_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.employees ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.employees_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: error_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.error_groups (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    fingerprint text COLLATE pg_catalog."C",
    code text COLLATE pg_catalog."C",
    error_type text COLLATE pg_catalog."C",
    message text COLLATE pg_catalog."C",
    tool text COLLATE pg_catalog."C",
    backtrace text COLLATE pg_catalog."C",
    request_id text COLLATE pg_catalog."C",
    first_seen_at text COLLATE pg_catalog."C",
    last_seen_at text COLLATE pg_catalog."C",
    count bigint DEFAULT 0,
    status text DEFAULT 'open'::text COLLATE pg_catalog."C",
    status_changed_at text COLLATE pg_catalog."C",
    status_changed_by text COLLATE pg_catalog."C",
    notified_at text COLLATE pg_catalog."C"
);


--
-- Name: error_groups_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.error_groups ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.error_groups_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: error_occurrences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.error_occurrences (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    group_id text COLLATE pg_catalog."C",
    at text COLLATE pg_catalog."C",
    request_id text COLLATE pg_catalog."C",
    kind text COLLATE pg_catalog."C",
    tool text COLLATE pg_catalog."C",
    actor text COLLATE pg_catalog."C",
    message text COLLATE pg_catalog."C",
    total_ms text COLLATE pg_catalog."C"
);


--
-- Name: error_occurrences_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.error_occurrences ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.error_occurrences_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: fake_accounting_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fake_accounting_calls (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    intent_id text COLLATE pg_catalog."C",
    invoice_id text COLLATE pg_catalog."C",
    external_ref text COLLATE pg_catalog."C",
    total_ore bigint,
    at text COLLATE pg_catalog."C"
);


--
-- Name: fake_accounting_calls_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.fake_accounting_calls ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.fake_accounting_calls_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: henvendelser; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.henvendelser (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    kind text DEFAULT 'epost'::text COLLATE pg_catalog."C",
    status text DEFAULT 'ny'::text COLLATE pg_catalog."C",
    from_name text COLLATE pg_catalog."C",
    from_email text COLLATE pg_catalog."C",
    subject text COLLATE pg_catalog."C",
    body text COLLATE pg_catalog."C",
    received_at text COLLATE pg_catalog."C",
    message_ref text COLLATE pg_catalog."C",
    customer_id text COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    match text DEFAULT 'ingen'::text COLLATE pg_catalog."C",
    created_order_id text COLLATE pg_catalog."C",
    questions text COLLATE pg_catalog."C",
    marketing_consent bigint,
    handled_by text COLLATE pg_catalog."C",
    handled_at text COLLATE pg_catalog."C",
    note text COLLATE pg_catalog."C",
    request_id text COLLATE pg_catalog."C"
);


--
-- Name: henvendelser_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.henvendelser ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.henvendelser_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventory_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_movements (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    product_id text COLLATE pg_catalog."C",
    kind text COLLATE pg_catalog."C",
    quantity numeric,
    revision bigint,
    balance_after numeric,
    reason text COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    at text COLLATE pg_catalog."C",
    article_id text COLLATE pg_catalog."C",
    balance_updated bigint DEFAULT 1,
    by text COLLATE pg_catalog."C"
);


--
-- Name: inventory_movements_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inventory_movements ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventory_movements_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: job_processes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_processes (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    started_at text COLLATE pg_catalog."C",
    lock_key bigint
);


--
-- Name: job_processes_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.job_processes ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.job_processes_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: job_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_schedules (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    name text COLLATE pg_catalog."C",
    first_seen_at text COLLATE pg_catalog."C",
    last_occurrence text COLLATE pg_catalog."C",
    last_occurrence_at text COLLATE pg_catalog."C",
    last_job_id text COLLATE pg_catalog."C",
    last_enqueued bigint
);


--
-- Name: job_schedules_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.job_schedules ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.job_schedules_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jobs (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    kind text COLLATE pg_catalog."C",
    queue text COLLATE pg_catalog."C",
    arguments text COLLATE pg_catalog."C",
    state text DEFAULT 'queued'::text COLLATE pg_catalog."C",
    priority bigint DEFAULT 0,
    due_at text COLLATE pg_catalog."C",
    attempts bigint DEFAULT 0,
    max_attempts bigint,
    snoozes bigint DEFAULT 0,
    unique_key text COLLATE pg_catalog."C",
    enqueued_at text COLLATE pg_catalog."C",
    enqueued_by text COLLATE pg_catalog."C",
    claimed_by text COLLATE pg_catalog."C",
    started_at text COLLATE pg_catalog."C",
    finished_at text COLLATE pg_catalog."C",
    last_error text COLLATE pg_catalog."C",
    errors text COLLATE pg_catalog."C",
    note text COLLATE pg_catalog."C"
);


--
-- Name: jobs_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.jobs ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.jobs_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: mails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mails (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    "to" text COLLATE pg_catalog."C",
    subject text COLLATE pg_catalog."C",
    text text COLLATE pg_catalog."C",
    html text COLLATE pg_catalog."C",
    reply_to text COLLATE pg_catalog."C",
    key text COLLATE pg_catalog."C",
    status text DEFAULT 'queued'::text COLLATE pg_catalog."C",
    attempts bigint DEFAULT 0,
    job_id text COLLATE pg_catalog."C",
    last_error text COLLATE pg_catalog."C",
    provider text COLLATE pg_catalog."C",
    provider_id text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C",
    sent_at text COLLATE pg_catalog."C"
);


--
-- Name: mails_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.mails ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.mails_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    type text COLLATE pg_catalog."C",
    recipient text COLLATE pg_catalog."C",
    text text COLLATE pg_catalog."C",
    link text COLLATE pg_catalog."C",
    subject_type text COLLATE pg_catalog."C",
    subject_id text COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    event_id text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C",
    read_at text COLLATE pg_catalog."C"
);


--
-- Name: notifications_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.notifications ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.notifications_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    source text COLLATE pg_catalog."C",
    open_questions text COLLATE pg_catalog."C",
    revision bigint DEFAULT 1,
    status text DEFAULT 'utkast'::text COLLATE pg_catalog."C",
    customer_id text COLLATE pg_catalog."C",
    event_date text COLLATE pg_catalog."C",
    end_date text COLLATE pg_catalog."C",
    delivery_address text COLLATE pg_catalog."C",
    lines text COLLATE pg_catalog."C",
    tags text COLLATE pg_catalog."C",
    department text COLLATE pg_catalog."C",
    price_mode text DEFAULT 'automatisk'::text COLLATE pg_catalog."C",
    discount_percent numeric,
    discount_ore_input bigint,
    price_reason text COLLATE pg_catalog."C",
    logistics text COLLATE pg_catalog."C",
    catalog_total_ore bigint DEFAULT 0,
    subtotal_ore bigint DEFAULT 0,
    discount_ore bigint DEFAULT 0,
    adjustment_ore bigint DEFAULT 0,
    total_ore bigint DEFAULT 0,
    requirements text COLLATE pg_catalog."C",
    pickup text COLLATE pg_catalog."C",
    return text COLLATE pg_catalog."C",
    accepted_snapshot_stale bigint,
    created_at text COLLATE pg_catalog."C"
);


--
-- Name: orders_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.orders ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.orders_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: plan_impact_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_impact_queue (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    catalog_change_id text COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    attempts bigint DEFAULT 0
);


--
-- Name: plan_impact_queue_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.plan_impact_queue ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.plan_impact_queue_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: plan_impacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_impacts (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    catalog_change_id text COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    status text COLLATE pg_catalog."C",
    detail text COLLATE pg_catalog."C",
    plan_revision bigint
);


--
-- Name: plan_impacts_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.plan_impacts ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.plan_impacts_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    revision bigint,
    status text COLLATE pg_catalog."C",
    fingerprint text COLLATE pg_catalog."C",
    activation text COLLATE pg_catalog."C",
    activated_at text COLLATE pg_catalog."C",
    activated_by text COLLATE pg_catalog."C",
    note text COLLATE pg_catalog."C",
    order_revision bigint,
    lines text COLLATE pg_catalog."C"
);


--
-- Name: plans_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.plans ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.plans_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    revision bigint DEFAULT 1,
    name text COLLATE pg_catalog."C",
    kind text COLLATE pg_catalog."C",
    unit text COLLATE pg_catalog."C",
    unit_price_ore bigint,
    stock_tracked bigint,
    units_owned bigint DEFAULT 0,
    manual_url text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C",
    article_id text COLLATE pg_catalog."C",
    department text COLLATE pg_catalog."C",
    department_revision bigint DEFAULT 1,
    requirements text COLLATE pg_catalog."C",
    lite_requirement_id text COLLATE pg_catalog."C",
    lite_recipe_id text COLLATE pg_catalog."C"
);


--
-- Name: products_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.products ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.products_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: push_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_subscriptions (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    account text COLLATE pg_catalog."C",
    endpoint text COLLATE pg_catalog."C",
    p256dh text COLLATE pg_catalog."C",
    auth text COLLATE pg_catalog."C",
    server_key text COLLATE pg_catalog."C",
    session text COLLATE pg_catalog."C",
    device text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C",
    tested_at text COLLATE pg_catalog."C"
);


--
-- Name: push_subscriptions_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.push_subscriptions ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.push_subscriptions_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: quotes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quotes (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    revision bigint DEFAULT 1,
    status text DEFAULT 'awaiting_response'::text COLLATE pg_catalog."C",
    offered_at text COLLATE pg_catalog."C",
    expires_at text COLLATE pg_catalog."C",
    responded_at text COLLATE pg_catalog."C",
    snapshot text COLLATE pg_catalog."C",
    basis text COLLATE pg_catalog."C",
    access_code text COLLATE pg_catalog."C"
);


--
-- Name: quotes_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.quotes ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.quotes_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: receipt; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.receipt (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    actor text COLLATE pg_catalog."C",
    tool text COLLATE pg_catalog."C",
    request_key text COLLATE pg_catalog."C",
    input_hash text COLLATE pg_catalog."C",
    redacted bigint,
    result text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C"
);


--
-- Name: receipt_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.receipt ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.receipt_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recipes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recipes (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    revision bigint DEFAULT 1,
    name text COLLATE pg_catalog."C",
    description text COLLATE pg_catalog."C",
    active bigint DEFAULT 1,
    lines text COLLATE pg_catalog."C"
);


--
-- Name: recipes_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recipes ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.recipes_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reservations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reservations (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    product_id text COLLATE pg_catalog."C",
    quantity numeric,
    needed_on text COLLATE pg_catalog."C",
    article_id text COLLATE pg_catalog."C"
);


--
-- Name: reservations_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reservations ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.reservations_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reviews (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    kind text COLLATE pg_catalog."C",
    status text DEFAULT 'pending'::text COLLATE pg_catalog."C",
    priority text DEFAULT 'normal'::text COLLATE pg_catalog."C",
    subject text COLLATE pg_catalog."C",
    proposal text COLLATE pg_catalog."C",
    source text COLLATE pg_catalog."C",
    idempotency_key text COLLATE pg_catalog."C",
    title text COLLATE pg_catalog."C",
    summary text COLLATE pg_catalog."C",
    requested_by text COLLATE pg_catalog."C",
    requested_at text COLLATE pg_catalog."C",
    due_at text COLLATE pg_catalog."C",
    reviewed_by text COLLATE pg_catalog."C",
    reviewed_at text COLLATE pg_catalog."C",
    note text COLLATE pg_catalog."C",
    subject_id text COLLATE pg_catalog."C",
    proposal_id text COLLATE pg_catalog."C"
);


--
-- Name: reviews_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reviews ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.reviews_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: saved_queries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_queries (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    account text COLLATE pg_catalog."C",
    page text COLLATE pg_catalog."C",
    query text COLLATE pg_catalog."C"
);


--
-- Name: saved_queries_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.saved_queries ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.saved_queries_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: schema_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_history (
    seq bigint NOT NULL,
    statement text NOT NULL,
    applied_at text NOT NULL,
    module text,
    migration text
);


--
-- Name: schema_history_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.schema_history ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.schema_history_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    account_id text COLLATE pg_catalog."C",
    token_hash text COLLATE pg_catalog."C",
    created_at text COLLATE pg_catalog."C",
    last_seen_at text COLLATE pg_catalog."C"
);


--
-- Name: sessions_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sessions ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.sessions_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: setting; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.setting (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    key text COLLATE pg_catalog."C",
    value text COLLATE pg_catalog."C"
);


--
-- Name: setting_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.setting ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.setting_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sign_in_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sign_in_attempts (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    strategy text COLLATE pg_catalog."C",
    state_hash text COLLATE pg_catalog."C",
    nonce text COLLATE pg_catalog."C",
    verifier text COLLATE pg_catalog."C",
    purpose text COLLATE pg_catalog."C",
    setup_hash text COLLATE pg_catalog."C",
    account_name text COLLATE pg_catalog."C",
    display_name text COLLATE pg_catalog."C",
    expires_at text COLLATE pg_catalog."C"
);


--
-- Name: sign_in_attempts_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sign_in_attempts ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.sign_in_attempts_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stock_levels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_levels (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    product_id text COLLATE pg_catalog."C",
    on_hand bigint DEFAULT 0,
    revision bigint DEFAULT 0
);


--
-- Name: stock_levels_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.stock_levels ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.stock_levels_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transfers (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    target_type text COLLATE pg_catalog."C",
    target_id text COLLATE pg_catalog."C",
    from_department text COLLATE pg_catalog."C",
    to_department text COLLATE pg_catalog."C",
    note text COLLATE pg_catalog."C",
    by text COLLATE pg_catalog."C",
    at text COLLATE pg_catalog."C"
);


--
-- Name: transfers_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.transfers ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.transfers_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: unavailabilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.unavailabilities (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    employee_id text COLLATE pg_catalog."C",
    start_date text COLLATE pg_catalog."C",
    end_date text COLLATE pg_catalog."C",
    whole_day bigint DEFAULT 1,
    start_time text COLLATE pg_catalog."C",
    end_time text COLLATE pg_catalog."C",
    private_note text COLLATE pg_catalog."C",
    version bigint DEFAULT 1
);


--
-- Name: unavailabilities_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.unavailabilities ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.unavailabilities_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: work_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_sessions (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    assignment_id text COLLATE pg_catalog."C",
    employee_id text COLLATE pg_catalog."C",
    started_at text COLLATE pg_catalog."C",
    ended_at text COLLATE pg_catalog."C",
    duration_seconds bigint,
    note text COLLATE pg_catalog."C",
    source text DEFAULT 'live'::text COLLATE pg_catalog."C"
);


--
-- Name: work_sessions_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.work_sessions ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.work_sessions_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: workflows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflows (
    seq bigint NOT NULL,
    id text NOT NULL COLLATE pg_catalog."C",
    key text COLLATE pg_catalog."C",
    request_id text COLLATE pg_catalog."C",
    kind text COLLATE pg_catalog."C",
    order_id text COLLATE pg_catalog."C",
    customer_id text COLLATE pg_catalog."C",
    due_at text COLLATE pg_catalog."C",
    status text DEFAULT 'planlagt'::text COLLATE pg_catalog."C",
    executed_at text COLLATE pg_catalog."C",
    note text COLLATE pg_catalog."C",
    subject_id text COLLATE pg_catalog."C"
);


--
-- Name: workflows_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.workflows ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.workflows_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Data for Name: access_tokens; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: account_identities; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: accounts; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.accounts OVERRIDING SYSTEM VALUE VALUES (1, 'acc_f0fg323qa6w96q9r', 'ada', NULL, 'person', 'admin', 'ada@example.no', 'active', '2026-03-01T09:00:00Z', 'admin:ada', NULL);


--
-- Data for Name: articles; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: assignment_overrides; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: assignments; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: attachment_contents; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: attachments; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: audit; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (1, 'aud_y00hc8c7c5yzh2sa', '2026-03-01T09:00:00Z', 'admin:ada', 'accounts_create', 'ok', 'account', 'acc_f0fg323qa6w96q9r', NULL, NULL, 'req_zd3t02prwb7qqmjt', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (2, 'aud_njbkdjfv3jk5ppdj', '2026-03-01T09:00:00Z', 'admin:ada', 'settings_set', 'ok', 'setting', 'lenker.base_url', NULL, NULL, 'req_zq2b1x5qb81fqrsd', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (3, 'aud_zqmavzwc2fxq9bbg', '2026-03-01T09:00:00Z', 'admin:ada', 'settings_set', 'ok', 'setting', NULL, NULL, NULL, 'req_zq2b1x5qb81fqrsd', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (4, 'aud_d8m838czdrhgzn18', '2026-03-01T09:00:00Z', 'admin:ada', 'debug_schedule', 'ok', 'workflow', 'wf_26eesc0vx0hpg6dx', NULL, NULL, 'req_8jpxvhvbs3t6s7bc', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (5, 'aud_b0kefm8e9gqq5vsd', '2026-03-01T09:00:00Z', 'admin:ada', 'debug_schedule', 'ok', 'workflow', 'wf_czctybdwc2vzvg9r', NULL, NULL, 'req_es9vx1hkgba91d49', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (6, 'aud_vdr2qjgg1b88n0kb', '2026-03-01T09:00:00Z', 'admin:ada', 'debug_schedule', 'ok', 'workflow', 'wf_n3q7zjeyr20dwz9a', NULL, NULL, 'req_j5zd1pksrbj2es9k', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (7, 'aud_qf9baewp6vjnzc24', '2026-03-01T09:00:00Z', 'admin:ada', 'debug_schedule', 'ok', 'workflow', 'wf_pgc03mnqe18eqbfz', NULL, NULL, 'req_b1y1bjyr3gm0xrmt', NULL, NULL);


--
-- Data for Name: bookings; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: catalog_changes; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: checklist_items; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: choice_groups; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: confirmation; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: consumption_commands; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: error_groups; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: error_occurrences; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: fake_accounting_calls; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: henvendelser; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: inventory_movements; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: job_processes; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: job_schedules; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.job_schedules OVERRIDING SYSTEM VALUE VALUES (1, 'jsc_jaw80768xacvt0cw', 'attachments_sweep', '2026-03-01T09:00:00Z', '2026-03-01T03:30', '2026-03-01T02:30:00Z', NULL, NULL);


--
-- Data for Name: jobs; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.jobs OVERRIDING SYSTEM VALUE VALUES (1, 'job_ypsp61w037b48agj', 'run_workflow', 'workflows', '{"workflow_id":"wf_26eesc0vx0hpg6dx"}', 'queued', 0, '2026-03-01T10:00:00Z', 0, 3, 0, 'b591b030aab9c9bc39077e21f60005d937a5906403cfa73a18591c895c62150f', '2026-03-01T09:00:00Z', 'admin:ada', NULL, NULL, NULL, NULL, '[]', NULL);
INSERT INTO public.jobs OVERRIDING SYSTEM VALUE VALUES (2, 'job_n4rmr3ewsgfmebem', 'run_workflow', 'workflows', '{"workflow_id":"wf_czctybdwc2vzvg9r"}', 'queued', 0, '2026-03-01T11:00:00Z', 0, 3, 0, '130383c4911d0b7752bfd64c3c8daaed9e28533ca60d3607c56334e7d0e8c932', '2026-03-01T09:00:00Z', 'admin:ada', NULL, NULL, NULL, NULL, '[]', NULL);
INSERT INTO public.jobs OVERRIDING SYSTEM VALUE VALUES (3, 'job_zwpxh3z1avrg9bnj', 'run_workflow', 'workflows', '{"workflow_id":"wf_n3q7zjeyr20dwz9a"}', 'queued', 0, '2026-03-01T12:00:00Z', 0, 3, 0, '195f529eeba890d69428f6b2bbacedb5742381628e8cc006c148c39a25395f45', '2026-03-01T09:00:00Z', 'admin:ada', NULL, NULL, NULL, NULL, '[]', NULL);
INSERT INTO public.jobs OVERRIDING SYSTEM VALUE VALUES (4, 'job_n506nh5xp5tyyf0e', 'run_workflow', 'workflows', '{"workflow_id":"wf_pgc03mnqe18eqbfz"}', 'queued', 0, '2026-03-01T13:00:00Z', 0, 3, 0, '182318e233617316389e64941321217f64fa651920346ec9b16d58fa7ed2126a', '2026-03-01T09:00:00Z', 'admin:ada', NULL, NULL, NULL, NULL, '[]', NULL);
INSERT INTO public.jobs OVERRIDING SYSTEM VALUE VALUES (5, 'job_9m5javawcap7mkp9', 'send_queued_mail', 'mail', '{"mail_id":"mail_dtn1z5mxahjt9pv6"}', 'queued', 0, '2026-03-01T09:00:00Z', 0, 7, 0, '5358365f7368fab6f2ffa3b18cf711e148e720d65ba54ca92c2f329a7b7ba883', '2026-03-01T09:00:00Z', 'system', NULL, NULL, NULL, NULL, '[]', NULL);


--
-- Data for Name: mails; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.mails OVERRIDING SYSTEM VALUE VALUES (1, 'mail_dtn1z5mxahjt9pv6', 'kari@example.no', 'Hei', 'Velkommen', NULL, NULL, NULL, 'queued', 0, 'job_9m5javawcap7mkp9', NULL, NULL, NULL, '2026-03-01T09:00:00Z', NULL);


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: plan_impact_queue; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: plan_impacts; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: plans; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: push_subscriptions; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: quotes; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: receipt; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: recipes; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: reservations; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: reviews; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: saved_queries; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: schema_history; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (1, 'core major 1 opened this database', '2026-10-28T06:25:49Z', 'tun-core', 'core-major-1');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (2, 'CREATE TABLE "attachment_contents" ("id" TEXT COLLATE "C" PRIMARY KEY,
                                         "content" BYTEA NOT NULL)', '2026-10-28T06:25:49Z', 'core', 'core_0001_create_attachment_contents');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (3, 'CREATE TABLE "audit" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "at" TEXT COLLATE "C", "actor" TEXT COLLATE "C", "tool" TEXT COLLATE "C", "outcome" TEXT COLLATE "C", "entity_type" TEXT COLLATE "C", "entity_id" TEXT COLLATE "C", "request_key" TEXT COLLATE "C", "error_code" TEXT COLLATE "C", "request_id" TEXT COLLATE "C", "reason" TEXT COLLATE "C", "credential" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0002_create_audit');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (4, 'CREATE TABLE "receipt" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "actor" TEXT COLLATE "C", "tool" TEXT COLLATE "C", "request_key" TEXT COLLATE "C", "input_hash" TEXT COLLATE "C", "redacted" BIGINT, "result" TEXT COLLATE "C", "created_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0003_create_receipt');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (5, 'CREATE TABLE "confirmation" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "token_hash" TEXT COLLATE "C", "actor" TEXT COLLATE "C", "tool" TEXT COLLATE "C", "input_hash" TEXT COLLATE "C", "expires_at" TEXT COLLATE "C", "request_id" TEXT COLLATE "C", "used_at" TEXT COLLATE "C", "created_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0004_create_confirmation');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (6, 'CREATE TABLE "setting" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "key" TEXT COLLATE "C", "value" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0005_create_setting');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (7, 'CREATE TABLE "fake_accounting_calls" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "intent_id" TEXT COLLATE "C", "invoice_id" TEXT COLLATE "C", "external_ref" TEXT COLLATE "C", "total_ore" BIGINT, "at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0006_create_fake_accounting_calls');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (8, 'CREATE TABLE "jobs" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "kind" TEXT COLLATE "C", "queue" TEXT COLLATE "C", "arguments" TEXT COLLATE "C", "state" TEXT COLLATE "C" DEFAULT ''queued'', "priority" BIGINT DEFAULT 0, "due_at" TEXT COLLATE "C", "attempts" BIGINT DEFAULT 0, "max_attempts" BIGINT, "snoozes" BIGINT DEFAULT 0, "unique_key" TEXT COLLATE "C", "enqueued_at" TEXT COLLATE "C", "enqueued_by" TEXT COLLATE "C", "claimed_by" TEXT COLLATE "C", "started_at" TEXT COLLATE "C", "finished_at" TEXT COLLATE "C", "last_error" TEXT COLLATE "C", "errors" TEXT COLLATE "C", "note" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0007_create_jobs');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (9, 'CREATE TABLE "job_schedules" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "name" TEXT COLLATE "C", "first_seen_at" TEXT COLLATE "C", "last_occurrence" TEXT COLLATE "C", "last_occurrence_at" TEXT COLLATE "C", "last_job_id" TEXT COLLATE "C", "last_enqueued" BIGINT)', '2026-10-28T06:25:49Z', 'core', 'core_0008_create_job_schedules');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (10, 'CREATE TABLE "job_processes" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "started_at" TEXT COLLATE "C", "lock_key" BIGINT)', '2026-10-28T06:25:49Z', 'core', 'core_0009_create_job_processes');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (11, 'CREATE TABLE "mails" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "to" TEXT COLLATE "C", "subject" TEXT COLLATE "C", "text" TEXT COLLATE "C", "html" TEXT COLLATE "C", "reply_to" TEXT COLLATE "C", "key" TEXT COLLATE "C", "status" TEXT COLLATE "C" DEFAULT ''queued'', "attempts" BIGINT DEFAULT 0, "job_id" TEXT COLLATE "C", "last_error" TEXT COLLATE "C", "provider" TEXT COLLATE "C", "provider_id" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "sent_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0010_create_mails');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (12, 'CREATE TABLE "attachments" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "entity" TEXT COLLATE "C", "record_id" TEXT COLLATE "C", "filename" TEXT COLLATE "C", "content_type" TEXT COLLATE "C", "size" BIGINT, "width" BIGINT, "height" BIGINT, "sha256" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "created_by" TEXT COLLATE "C", "account" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0011_create_attachments');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (13, 'CREATE TABLE "workflows" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "key" TEXT COLLATE "C", "request_id" TEXT COLLATE "C", "kind" TEXT COLLATE "C", "order_id" TEXT COLLATE "C", "customer_id" TEXT COLLATE "C", "due_at" TEXT COLLATE "C", "status" TEXT COLLATE "C" DEFAULT ''planlagt'', "executed_at" TEXT COLLATE "C", "note" TEXT COLLATE "C", "subject_id" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0012_create_workflows');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (14, 'CREATE TABLE "error_groups" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "fingerprint" TEXT COLLATE "C", "code" TEXT COLLATE "C", "error_type" TEXT COLLATE "C", "message" TEXT COLLATE "C", "tool" TEXT COLLATE "C", "backtrace" TEXT COLLATE "C", "request_id" TEXT COLLATE "C", "first_seen_at" TEXT COLLATE "C", "last_seen_at" TEXT COLLATE "C", "count" BIGINT DEFAULT 0, "status" TEXT COLLATE "C" DEFAULT ''open'', "status_changed_at" TEXT COLLATE "C", "status_changed_by" TEXT COLLATE "C", "notified_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0013_create_error_groups');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (15, 'CREATE TABLE "error_occurrences" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "group_id" TEXT COLLATE "C", "at" TEXT COLLATE "C", "request_id" TEXT COLLATE "C", "kind" TEXT COLLATE "C", "tool" TEXT COLLATE "C", "actor" TEXT COLLATE "C", "message" TEXT COLLATE "C", "total_ms" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0014_create_error_occurrences');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (16, 'CREATE TABLE "accounts" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "name" TEXT COLLATE "C", "display_name" TEXT COLLATE "C", "kind" TEXT COLLATE "C", "role" TEXT COLLATE "C", "email" TEXT COLLATE "C", "status" TEXT COLLATE "C" DEFAULT ''active'', "created_at" TEXT COLLATE "C", "created_by" TEXT COLLATE "C", "invited_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0015_create_accounts');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (17, 'CREATE TABLE "access_tokens" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "account_id" TEXT COLLATE "C", "label" TEXT COLLATE "C", "role" TEXT COLLATE "C", "prefix" TEXT COLLATE "C", "token_hash" TEXT COLLATE "C", "expires_at" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "created_by" TEXT COLLATE "C", "last_used_at" TEXT COLLATE "C", "revoked_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0016_create_access_tokens');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (18, 'CREATE TABLE "sessions" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "account_id" TEXT COLLATE "C", "token_hash" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "last_seen_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0017_create_sessions');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (53, 'CREATE INDEX "idx_jobs_kind_unique_key" ON "jobs" ("kind", "unique_key")', '2026-10-28T06:25:49Z', 'core', 'core_0026_idx_jobs_kind_unique_key');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (19, 'CREATE TABLE "account_identities" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "account_id" TEXT COLLATE "C", "strategy" TEXT COLLATE "C", "issuer" TEXT COLLATE "C", "subject" TEXT COLLATE "C", "email" TEXT COLLATE "C", "linked_at" TEXT COLLATE "C", "last_used_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0018_create_account_identities');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (20, 'CREATE TABLE "sign_in_attempts" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "strategy" TEXT COLLATE "C", "state_hash" TEXT COLLATE "C", "nonce" TEXT COLLATE "C", "verifier" TEXT COLLATE "C", "purpose" TEXT COLLATE "C", "setup_hash" TEXT COLLATE "C", "account_name" TEXT COLLATE "C", "display_name" TEXT COLLATE "C", "expires_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0019_create_sign_in_attempts');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (21, 'CREATE TABLE "push_subscriptions" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "account" TEXT COLLATE "C", "endpoint" TEXT COLLATE "C", "p256dh" TEXT COLLATE "C", "auth" TEXT COLLATE "C", "server_key" TEXT COLLATE "C", "session" TEXT COLLATE "C", "device" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "tested_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0020_create_push_subscriptions');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (22, 'CREATE TABLE "saved_queries" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "account" TEXT COLLATE "C", "page" TEXT COLLATE "C", "query" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'core', 'core_0021_create_saved_queries');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (23, 'CREATE TABLE "customers" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "marketing_consent" BIGINT, "consent_source" TEXT COLLATE "C", "consent_at" TEXT COLLATE "C", "erased" BIGINT, "erased_at" TEXT COLLATE "C", "revision" BIGINT DEFAULT 1, "name" TEXT COLLATE "C", "email" TEXT COLLATE "C", "phone" TEXT COLLATE "C", "notes" TEXT COLLATE "C", "completed_orders" BIGINT DEFAULT 0, "created_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'customers', 'customers_0001_create_customers');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (24, 'CREATE TABLE "products" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "revision" BIGINT DEFAULT 1, "name" TEXT COLLATE "C", "kind" TEXT COLLATE "C", "unit" TEXT COLLATE "C", "unit_price_ore" BIGINT, "stock_tracked" BIGINT, "units_owned" BIGINT DEFAULT 0, "manual_url" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "article_id" TEXT COLLATE "C", "department" TEXT COLLATE "C", "department_revision" BIGINT DEFAULT 1, "requirements" TEXT COLLATE "C", "lite_requirement_id" TEXT COLLATE "C", "lite_recipe_id" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'catalog', 'catalog_0001_create_products');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (25, 'CREATE TABLE "recipes" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "revision" BIGINT DEFAULT 1, "name" TEXT COLLATE "C", "description" TEXT COLLATE "C", "active" BIGINT DEFAULT 1, "lines" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'catalog', 'catalog_0002_create_recipes');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (26, 'CREATE TABLE "choice_groups" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "revision" BIGINT DEFAULT 1, "name" TEXT COLLATE "C", "active" BIGINT DEFAULT 1, "members" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'catalog', 'catalog_0003_create_choice_groups');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (27, 'CREATE TABLE "catalog_changes" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "resource_type" TEXT COLLATE "C", "resource_id" TEXT COLLATE "C", "operation" TEXT COLLATE "C", "changed_fields" TEXT COLLATE "C", "at" TEXT COLLATE "C", "by" TEXT COLLATE "C", "product_id" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'catalog', 'catalog_0004_create_catalog_changes');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (28, 'CREATE TABLE "stock_levels" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "product_id" TEXT COLLATE "C", "on_hand" BIGINT DEFAULT 0, "revision" BIGINT DEFAULT 0)', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0001_create_stock_levels');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (29, 'CREATE TABLE "articles" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "revision" BIGINT DEFAULT 1, "name" TEXT COLLATE "C", "sku" TEXT COLLATE "C", "unit" TEXT COLLATE "C", "package_size" NUMERIC, "balance" NUMERIC DEFAULT 0, "movement_revision" BIGINT DEFAULT 0, "min_level" NUMERIC, "max_level" NUMERIC, "cost_price_ore" BIGINT, "supplier" TEXT COLLATE "C", "lead_days" BIGINT DEFAULT 0, "department" TEXT COLLATE "C", "department_revision" BIGINT DEFAULT 1, "active" BIGINT DEFAULT 1, "product_id" TEXT COLLATE "C", "created_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0002_create_articles');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (30, 'CREATE TABLE "inventory_movements" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "product_id" TEXT COLLATE "C", "kind" TEXT COLLATE "C", "quantity" NUMERIC, "revision" BIGINT, "balance_after" NUMERIC, "reason" TEXT COLLATE "C", "order_id" TEXT COLLATE "C", "at" TEXT COLLATE "C", "article_id" TEXT COLLATE "C", "balance_updated" BIGINT DEFAULT 1, "by" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0003_create_inventory_movements');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (31, 'CREATE TABLE "reservations" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "order_id" TEXT COLLATE "C", "product_id" TEXT COLLATE "C", "quantity" NUMERIC, "needed_on" TEXT COLLATE "C", "article_id" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0004_create_reservations');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (32, 'CREATE TABLE "transfers" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "target_type" TEXT COLLATE "C", "target_id" TEXT COLLATE "C", "from_department" TEXT COLLATE "C", "to_department" TEXT COLLATE "C", "note" TEXT COLLATE "C", "by" TEXT COLLATE "C", "at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0005_create_transfers');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (33, 'CREATE TABLE "consumption_commands" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "order_id" TEXT COLLATE "C", "order_revision" BIGINT, "effective_date" TEXT COLLATE "C", "fingerprint" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0006_create_consumption_commands');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (34, 'CREATE TABLE "reviews" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "kind" TEXT COLLATE "C", "status" TEXT COLLATE "C" DEFAULT ''pending'', "priority" TEXT COLLATE "C" DEFAULT ''normal'', "subject" TEXT COLLATE "C", "proposal" TEXT COLLATE "C", "source" TEXT COLLATE "C", "idempotency_key" TEXT COLLATE "C", "title" TEXT COLLATE "C", "summary" TEXT COLLATE "C", "requested_by" TEXT COLLATE "C", "requested_at" TEXT COLLATE "C", "due_at" TEXT COLLATE "C", "reviewed_by" TEXT COLLATE "C", "reviewed_at" TEXT COLLATE "C", "note" TEXT COLLATE "C", "subject_id" TEXT COLLATE "C", "proposal_id" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'reviews', 'reviews_0001_create_reviews');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (54, 'CREATE INDEX "idx_jobs_claimed_by" ON "jobs" ("claimed_by")', '2026-10-28T06:25:49Z', 'core', 'core_0027_idx_jobs_claimed_by');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (55, 'CREATE INDEX "idx_mails_status" ON "mails" ("status")', '2026-10-28T06:25:49Z', 'core', 'core_0028_idx_mails_status');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (56, 'CREATE INDEX "idx_mails_key" ON "mails" ("key")', '2026-10-28T06:25:49Z', 'core', 'core_0029_idx_mails_key');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (57, 'CREATE INDEX "idx_mails_to" ON "mails" ("to")', '2026-10-28T06:25:49Z', 'core', 'core_0030_idx_mails_to');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (35, 'CREATE TABLE "orders" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "source" TEXT COLLATE "C", "open_questions" TEXT COLLATE "C", "revision" BIGINT DEFAULT 1, "status" TEXT COLLATE "C" DEFAULT ''utkast'', "customer_id" TEXT COLLATE "C", "event_date" TEXT COLLATE "C", "end_date" TEXT COLLATE "C", "delivery_address" TEXT COLLATE "C", "lines" TEXT COLLATE "C", "tags" TEXT COLLATE "C", "department" TEXT COLLATE "C", "price_mode" TEXT COLLATE "C" DEFAULT ''automatisk'', "discount_percent" NUMERIC, "discount_ore_input" BIGINT, "price_reason" TEXT COLLATE "C", "logistics" TEXT COLLATE "C", "catalog_total_ore" BIGINT DEFAULT 0, "subtotal_ore" BIGINT DEFAULT 0, "discount_ore" BIGINT DEFAULT 0, "adjustment_ore" BIGINT DEFAULT 0, "total_ore" BIGINT DEFAULT 0, "requirements" TEXT COLLATE "C", "pickup" TEXT COLLATE "C", "return" TEXT COLLATE "C", "accepted_snapshot_stale" BIGINT, "created_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'orders', 'orders_0001_create_orders');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (36, 'CREATE TABLE "bookings" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "order_id" TEXT COLLATE "C", "product_id" TEXT COLLATE "C", "quantity" BIGINT, "from_date" TEXT COLLATE "C", "to_date" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'orders', 'orders_0002_create_bookings');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (37, 'CREATE TABLE "quotes" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "order_id" TEXT COLLATE "C", "revision" BIGINT DEFAULT 1, "status" TEXT COLLATE "C" DEFAULT ''awaiting_response'', "offered_at" TEXT COLLATE "C", "expires_at" TEXT COLLATE "C", "responded_at" TEXT COLLATE "C", "snapshot" TEXT COLLATE "C", "basis" TEXT COLLATE "C", "access_code" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'orders', 'orders_0003_create_quotes');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (38, 'CREATE TABLE "checklist_items" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "order_id" TEXT COLLATE "C", "order_line_id" TEXT COLLATE "C", "origin" TEXT COLLATE "C" DEFAULT ''manual'', "source_key" TEXT COLLATE "C", "description" TEXT COLLATE "C", "category" TEXT COLLATE "C", "computed_quantity" NUMERIC, "done_quantity" NUMERIC, "done" BIGINT)', '2026-10-28T06:25:49Z', 'orders', 'orders_0004_create_checklist_items');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (39, 'CREATE TABLE "plans" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "order_id" TEXT COLLATE "C", "revision" BIGINT, "status" TEXT COLLATE "C", "fingerprint" TEXT COLLATE "C", "activation" TEXT COLLATE "C", "activated_at" TEXT COLLATE "C", "activated_by" TEXT COLLATE "C", "note" TEXT COLLATE "C", "order_revision" BIGINT, "lines" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'orders', 'orders_0005_create_plans');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (40, 'CREATE TABLE "plan_impacts" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "catalog_change_id" TEXT COLLATE "C", "order_id" TEXT COLLATE "C", "status" TEXT COLLATE "C", "detail" TEXT COLLATE "C", "plan_revision" BIGINT)', '2026-10-28T06:25:49Z', 'orders', 'orders_0006_create_plan_impacts');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (41, 'CREATE TABLE "plan_impact_queue" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "catalog_change_id" TEXT COLLATE "C", "order_id" TEXT COLLATE "C", "attempts" BIGINT DEFAULT 0)', '2026-10-28T06:25:49Z', 'orders', 'orders_0007_create_plan_impact_queue');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (42, 'CREATE TABLE "employees" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "name" TEXT COLLATE "C", "actor" TEXT COLLATE "C", "role" TEXT COLLATE "C", "department" TEXT COLLATE "C", "auto_assign_in_department" BIGINT, "active" BIGINT DEFAULT 1, "created_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0001_create_employees');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (43, 'CREATE TABLE "assignments" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "order_id" TEXT COLLATE "C", "employee_id" TEXT COLLATE "C", "auto" BIGINT, "auto_department" TEXT COLLATE "C", "started_at" TEXT COLLATE "C", "ended_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0002_create_assignments');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (44, 'CREATE TABLE "assignment_overrides" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "assignment_id" TEXT COLLATE "C", "order_id" TEXT COLLATE "C", "employee_id" TEXT COLLATE "C", "reason" TEXT COLLATE "C", "conflict_ids" TEXT COLLATE "C", "conflict_summary" TEXT COLLATE "C", "created_by" TEXT COLLATE "C", "created_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0003_create_assignment_overrides');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (45, 'CREATE TABLE "unavailabilities" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "employee_id" TEXT COLLATE "C", "start_date" TEXT COLLATE "C", "end_date" TEXT COLLATE "C", "whole_day" BIGINT DEFAULT 1, "start_time" TEXT COLLATE "C", "end_time" TEXT COLLATE "C", "private_note" TEXT COLLATE "C", "version" BIGINT DEFAULT 1)', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0004_create_unavailabilities');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (46, 'CREATE TABLE "work_sessions" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "order_id" TEXT COLLATE "C", "assignment_id" TEXT COLLATE "C", "employee_id" TEXT COLLATE "C", "started_at" TEXT COLLATE "C", "ended_at" TEXT COLLATE "C", "duration_seconds" BIGINT, "note" TEXT COLLATE "C", "source" TEXT COLLATE "C" DEFAULT ''live'')', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0005_create_work_sessions');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (47, 'CREATE TABLE "notifications" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "type" TEXT COLLATE "C", "recipient" TEXT COLLATE "C", "text" TEXT COLLATE "C", "link" TEXT COLLATE "C", "subject_type" TEXT COLLATE "C", "subject_id" TEXT COLLATE "C", "order_id" TEXT COLLATE "C", "event_id" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "read_at" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'notifications', 'notifications_0001_create_notifications');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (48, 'CREATE TABLE "henvendelser" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "kind" TEXT COLLATE "C" DEFAULT ''epost'', "status" TEXT COLLATE "C" DEFAULT ''ny'', "from_name" TEXT COLLATE "C", "from_email" TEXT COLLATE "C", "subject" TEXT COLLATE "C", "body" TEXT COLLATE "C", "received_at" TEXT COLLATE "C", "message_ref" TEXT COLLATE "C", "customer_id" TEXT COLLATE "C", "order_id" TEXT COLLATE "C", "match" TEXT COLLATE "C" DEFAULT ''ingen'', "created_order_id" TEXT COLLATE "C", "questions" TEXT COLLATE "C", "marketing_consent" BIGINT, "handled_by" TEXT COLLATE "C", "handled_at" TEXT COLLATE "C", "note" TEXT COLLATE "C", "request_id" TEXT COLLATE "C")', '2026-10-28T06:25:49Z', 'inbox', 'inbox_0001_create_henvendelser');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (49, 'CREATE INDEX "idx_audit_entity_type_entity_id" ON "audit" ("entity_type", "entity_id")', '2026-10-28T06:25:49Z', 'core', 'core_0022_idx_audit_entity_type_entity_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (50, 'CREATE INDEX "idx_fake_accounting_calls_intent_id" ON "fake_accounting_calls" ("intent_id")', '2026-10-28T06:25:49Z', 'core', 'core_0023_idx_fake_accounting_calls_intent_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (51, 'CREATE INDEX "idx_fake_accounting_calls_invoice_id" ON "fake_accounting_calls" ("invoice_id")', '2026-10-28T06:25:49Z', 'core', 'core_0024_idx_fake_accounting_calls_invoice_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (52, 'CREATE INDEX "idx_jobs_state_queue_due_at" ON "jobs" ("state", "queue", "due_at")', '2026-10-28T06:25:49Z', 'core', 'core_0025_idx_jobs_state_queue_due_at');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (58, 'CREATE INDEX "idx_attachments_entity_record_id" ON "attachments" ("entity", "record_id")', '2026-10-28T06:25:49Z', 'core', 'core_0031_idx_attachments_entity_record_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (59, 'CREATE INDEX "idx_workflows_order_id" ON "workflows" ("order_id")', '2026-10-28T06:25:49Z', 'core', 'core_0032_idx_workflows_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (60, 'CREATE INDEX "idx_workflows_status_due_at" ON "workflows" ("status", "due_at")', '2026-10-28T06:25:49Z', 'core', 'core_0033_idx_workflows_status_due_at');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (61, 'CREATE INDEX "idx_workflows_kind_key_status" ON "workflows" ("kind", "key", "status")', '2026-10-28T06:25:49Z', 'core', 'core_0034_idx_workflows_kind_key_status');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (62, 'CREATE INDEX "idx_error_groups_status_last_seen_at" ON "error_groups" ("status", "last_seen_at")', '2026-10-28T06:25:49Z', 'core', 'core_0035_idx_error_groups_status_last_seen_at');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (63, 'CREATE INDEX "idx_error_occurrences_group_id" ON "error_occurrences" ("group_id")', '2026-10-28T06:25:49Z', 'core', 'core_0036_idx_error_occurrences_group_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (64, 'CREATE INDEX "idx_access_tokens_account_id" ON "access_tokens" ("account_id")', '2026-10-28T06:25:49Z', 'core', 'core_0037_idx_access_tokens_account_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (65, 'CREATE INDEX "idx_sessions_account_id" ON "sessions" ("account_id")', '2026-10-28T06:25:49Z', 'core', 'core_0038_idx_sessions_account_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (66, 'CREATE INDEX "idx_account_identities_account_id" ON "account_identities" ("account_id")', '2026-10-28T06:25:49Z', 'core', 'core_0039_idx_account_identities_account_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (67, 'CREATE INDEX "idx_push_subscriptions_account" ON "push_subscriptions" ("account")', '2026-10-28T06:25:49Z', 'core', 'core_0040_idx_push_subscriptions_account');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (68, 'CREATE INDEX "idx_push_subscriptions_session" ON "push_subscriptions" ("session")', '2026-10-28T06:25:49Z', 'core', 'core_0041_idx_push_subscriptions_session');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (69, 'CREATE INDEX "idx_products_kind" ON "products" ("kind")', '2026-10-28T06:25:49Z', 'catalog', 'catalog_0005_idx_products_kind');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (70, 'CREATE INDEX "idx_products_article_id" ON "products" ("article_id")', '2026-10-28T06:25:49Z', 'catalog', 'catalog_0006_idx_products_article_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (71, 'CREATE INDEX "idx_articles_product_id" ON "articles" ("product_id")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0007_idx_articles_product_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (72, 'CREATE INDEX "idx_articles_department" ON "articles" ("department")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0008_idx_articles_department');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (73, 'CREATE INDEX "idx_inventory_movements_product_id_revision" ON "inventory_movements" ("product_id", "revision")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0009_idx_inventory_movements_product_id_revision');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (74, 'CREATE INDEX "idx_inventory_movements_article_id_revision" ON "inventory_movements" ("article_id", "revision")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0010_idx_inventory_movements_article_id_revision');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (75, 'CREATE INDEX "idx_inventory_movements_order_id" ON "inventory_movements" ("order_id")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0011_idx_inventory_movements_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (76, 'CREATE INDEX "idx_reservations_order_id" ON "reservations" ("order_id")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0012_idx_reservations_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (77, 'CREATE INDEX "idx_reservations_article_id" ON "reservations" ("article_id")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0013_idx_reservations_article_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (78, 'CREATE INDEX "idx_transfers_target_id" ON "transfers" ("target_id")', '2026-10-28T06:25:49Z', 'inventory', 'inventory_0014_idx_transfers_target_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (79, 'CREATE INDEX "idx_reviews_status" ON "reviews" ("status")', '2026-10-28T06:25:49Z', 'reviews', 'reviews_0002_idx_reviews_status');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (80, 'CREATE INDEX "idx_reviews_subject_id" ON "reviews" ("subject_id")', '2026-10-28T06:25:49Z', 'reviews', 'reviews_0003_idx_reviews_subject_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (81, 'CREATE INDEX "idx_reviews_proposal_id" ON "reviews" ("proposal_id")', '2026-10-28T06:25:49Z', 'reviews', 'reviews_0004_idx_reviews_proposal_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (82, 'CREATE INDEX "idx_orders_customer_id" ON "orders" ("customer_id")', '2026-10-28T06:25:49Z', 'orders', 'orders_0008_idx_orders_customer_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (83, 'CREATE INDEX "idx_orders_status" ON "orders" ("status")', '2026-10-28T06:25:49Z', 'orders', 'orders_0009_idx_orders_status');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (84, 'CREATE INDEX "idx_orders_event_date" ON "orders" ("event_date")', '2026-10-28T06:25:49Z', 'orders', 'orders_0010_idx_orders_event_date');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (85, 'CREATE INDEX "idx_bookings_product_id_from_date" ON "bookings" ("product_id", "from_date")', '2026-10-28T06:25:49Z', 'orders', 'orders_0011_idx_bookings_product_id_from_date');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (86, 'CREATE INDEX "idx_bookings_order_id" ON "bookings" ("order_id")', '2026-10-28T06:25:49Z', 'orders', 'orders_0012_idx_bookings_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (87, 'CREATE INDEX "idx_quotes_access_code" ON "quotes" ("access_code")', '2026-10-28T06:25:49Z', 'orders', 'orders_0013_idx_quotes_access_code');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (88, 'CREATE INDEX "idx_checklist_items_order_id" ON "checklist_items" ("order_id")', '2026-10-28T06:25:49Z', 'orders', 'orders_0014_idx_checklist_items_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (89, 'CREATE INDEX "idx_plans_order_id" ON "plans" ("order_id")', '2026-10-28T06:25:49Z', 'orders', 'orders_0015_idx_plans_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (90, 'CREATE INDEX "idx_plan_impacts_order_id" ON "plan_impacts" ("order_id")', '2026-10-28T06:25:49Z', 'orders', 'orders_0016_idx_plan_impacts_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (91, 'CREATE INDEX "idx_plan_impact_queue_catalog_change_id" ON "plan_impact_queue" ("catalog_change_id")', '2026-10-28T06:25:49Z', 'orders', 'orders_0017_idx_plan_impact_queue_catalog_change_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (92, 'CREATE INDEX "idx_employees_department" ON "employees" ("department")', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0006_idx_employees_department');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (93, 'CREATE INDEX "idx_assignments_order_id" ON "assignments" ("order_id")', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0007_idx_assignments_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (94, 'CREATE INDEX "idx_assignments_employee_id" ON "assignments" ("employee_id")', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0008_idx_assignments_employee_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (95, 'CREATE INDEX "idx_assignment_overrides_order_id" ON "assignment_overrides" ("order_id")', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0009_idx_assignment_overrides_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (96, 'CREATE INDEX "idx_unavailabilities_employee_id_start_date" ON "unavailabilities" ("employee_id", "start_date")', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0010_idx_unavailabilities_employee_id_start_date');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (97, 'CREATE INDEX "idx_work_sessions_order_id" ON "work_sessions" ("order_id")', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0011_idx_work_sessions_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (98, 'CREATE INDEX "idx_work_sessions_employee_id_ended_at" ON "work_sessions" ("employee_id", "ended_at")', '2026-10-28T06:25:49Z', 'staffing', 'staffing_0012_idx_work_sessions_employee_id_ended_at');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (99, 'CREATE INDEX "idx_notifications_recipient" ON "notifications" ("recipient")', '2026-10-28T06:25:49Z', 'notifications', 'notifications_0002_idx_notifications_recipient');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (100, 'CREATE INDEX "idx_henvendelser_order_id" ON "henvendelser" ("order_id")', '2026-10-28T06:25:49Z', 'inbox', 'inbox_0002_idx_henvendelser_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (101, 'CREATE INDEX "idx_henvendelser_customer_id" ON "henvendelser" ("customer_id")', '2026-10-28T06:25:49Z', 'inbox', 'inbox_0003_idx_henvendelser_customer_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (102, 'CREATE INDEX "idx_henvendelser_message_ref" ON "henvendelser" ("message_ref")', '2026-10-28T06:25:49Z', 'inbox', 'inbox_0004_idx_henvendelser_message_ref');


--
-- Data for Name: sessions; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: setting; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.setting OVERRIDING SYSTEM VALUE VALUES (1, 'set_kyce345zjh3aam5d', 'lenker.hemmelighet', '"5dd4e5d015f490db411a14ee840d2aed9a482bb328d29693bb348817d14a309b"');
INSERT INTO public.setting OVERRIDING SYSTEM VALUE VALUES (2, 'set_hk0z5g64tda1nt0p', 'push.hemmelighet', '"271abba8275a7d8577b7b8e5dc3cd61452ac456c23caa5645822056df5a8d30a"');
INSERT INTO public.setting OVERRIDING SYSTEM VALUE VALUES (3, 'set_0zbatrehxz0cc8wq', 'innboks.hemmelighet', '"bf7cef0355ffc248d3bbb0aa05126f956e4945f9fffedcd2ccc8a28844d4ddeb"');
INSERT INTO public.setting OVERRIDING SYSTEM VALUE VALUES (4, 'set_ghbxdynyze7aggwg', 'lenker.base_url', '"https://tenant.example"');


--
-- Data for Name: sign_in_attempts; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: stock_levels; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: transfers; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: unavailabilities; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: work_sessions; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: workflows; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.workflows OVERRIDING SYSTEM VALUE VALUES (1, 'wf_26eesc0vx0hpg6dx', NULL, NULL, 'debug_ping', NULL, NULL, '2026-03-01T10:00:00Z', 'planlagt', NULL, NULL, NULL);
INSERT INTO public.workflows OVERRIDING SYSTEM VALUE VALUES (2, 'wf_czctybdwc2vzvg9r', NULL, NULL, 'debug_ping', NULL, NULL, '2026-03-01T11:00:00Z', 'utført', NULL, NULL, NULL);
INSERT INTO public.workflows OVERRIDING SYSTEM VALUE VALUES (3, 'wf_n3q7zjeyr20dwz9a', NULL, NULL, 'debug_ping', NULL, NULL, '2026-03-01T12:00:00Z', 'avbrutt', NULL, NULL, NULL);
INSERT INTO public.workflows OVERRIDING SYSTEM VALUE VALUES (4, 'wf_pgc03mnqe18eqbfz', NULL, NULL, 'debug_ping', NULL, NULL, '2026-03-01T13:00:00Z', 'feilet', NULL, NULL, NULL);


--
-- Name: access_tokens_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.access_tokens_seq_seq', 1, false);


--
-- Name: account_identities_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.account_identities_seq_seq', 1, false);


--
-- Name: accounts_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.accounts_seq_seq', 1, true);


--
-- Name: articles_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.articles_seq_seq', 1, false);


--
-- Name: assignment_overrides_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.assignment_overrides_seq_seq', 1, false);


--
-- Name: assignments_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.assignments_seq_seq', 1, false);


--
-- Name: attachments_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.attachments_seq_seq', 1, false);


--
-- Name: audit_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.audit_seq_seq', 7, true);


--
-- Name: bookings_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.bookings_seq_seq', 1, false);


--
-- Name: catalog_changes_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.catalog_changes_seq_seq', 1, false);


--
-- Name: checklist_items_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.checklist_items_seq_seq', 1, false);


--
-- Name: choice_groups_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.choice_groups_seq_seq', 1, false);


--
-- Name: confirmation_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.confirmation_seq_seq', 1, false);


--
-- Name: consumption_commands_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.consumption_commands_seq_seq', 1, false);


--
-- Name: customers_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.customers_seq_seq', 1, false);


--
-- Name: employees_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.employees_seq_seq', 1, false);


--
-- Name: error_groups_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.error_groups_seq_seq', 1, false);


--
-- Name: error_occurrences_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.error_occurrences_seq_seq', 1, false);


--
-- Name: fake_accounting_calls_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.fake_accounting_calls_seq_seq', 1, false);


--
-- Name: henvendelser_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.henvendelser_seq_seq', 1, false);


--
-- Name: inventory_movements_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventory_movements_seq_seq', 1, false);


--
-- Name: job_processes_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.job_processes_seq_seq', 1, true);


--
-- Name: job_schedules_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.job_schedules_seq_seq', 1, true);


--
-- Name: jobs_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.jobs_seq_seq', 5, true);


--
-- Name: mails_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.mails_seq_seq', 1, true);


--
-- Name: notifications_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.notifications_seq_seq', 1, false);


--
-- Name: orders_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.orders_seq_seq', 1, false);


--
-- Name: plan_impact_queue_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.plan_impact_queue_seq_seq', 1, false);


--
-- Name: plan_impacts_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.plan_impacts_seq_seq', 1, false);


--
-- Name: plans_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.plans_seq_seq', 1, false);


--
-- Name: products_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.products_seq_seq', 1, false);


--
-- Name: push_subscriptions_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.push_subscriptions_seq_seq', 1, false);


--
-- Name: quotes_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.quotes_seq_seq', 1, false);


--
-- Name: receipt_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.receipt_seq_seq', 1, false);


--
-- Name: recipes_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recipes_seq_seq', 1, false);


--
-- Name: reservations_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reservations_seq_seq', 1, false);


--
-- Name: reviews_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reviews_seq_seq', 1, false);


--
-- Name: saved_queries_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.saved_queries_seq_seq', 1, false);


--
-- Name: schema_history_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.schema_history_seq_seq', 102, true);


--
-- Name: sessions_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sessions_seq_seq', 1, false);


--
-- Name: setting_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.setting_seq_seq', 4, true);


--
-- Name: sign_in_attempts_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sign_in_attempts_seq_seq', 1, false);


--
-- Name: stock_levels_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.stock_levels_seq_seq', 1, false);


--
-- Name: transfers_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.transfers_seq_seq', 1, false);


--
-- Name: unavailabilities_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.unavailabilities_seq_seq', 1, false);


--
-- Name: work_sessions_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.work_sessions_seq_seq', 1, false);


--
-- Name: workflows_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.workflows_seq_seq', 4, true);


--
-- Name: access_tokens access_tokens_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_tokens
    ADD CONSTRAINT access_tokens_id_key UNIQUE (id);


--
-- Name: access_tokens access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_tokens
    ADD CONSTRAINT access_tokens_pkey PRIMARY KEY (seq);


--
-- Name: account_identities account_identities_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_identities
    ADD CONSTRAINT account_identities_id_key UNIQUE (id);


--
-- Name: account_identities account_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_identities
    ADD CONSTRAINT account_identities_pkey PRIMARY KEY (seq);


--
-- Name: accounts accounts_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_id_key UNIQUE (id);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (seq);


--
-- Name: articles articles_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.articles
    ADD CONSTRAINT articles_id_key UNIQUE (id);


--
-- Name: articles articles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.articles
    ADD CONSTRAINT articles_pkey PRIMARY KEY (seq);


--
-- Name: assignment_overrides assignment_overrides_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignment_overrides
    ADD CONSTRAINT assignment_overrides_id_key UNIQUE (id);


--
-- Name: assignment_overrides assignment_overrides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignment_overrides
    ADD CONSTRAINT assignment_overrides_pkey PRIMARY KEY (seq);


--
-- Name: assignments assignments_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignments
    ADD CONSTRAINT assignments_id_key UNIQUE (id);


--
-- Name: assignments assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignments
    ADD CONSTRAINT assignments_pkey PRIMARY KEY (seq);


--
-- Name: attachment_contents attachment_contents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachment_contents
    ADD CONSTRAINT attachment_contents_pkey PRIMARY KEY (id);


--
-- Name: attachments attachments_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachments
    ADD CONSTRAINT attachments_id_key UNIQUE (id);


--
-- Name: attachments attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachments
    ADD CONSTRAINT attachments_pkey PRIMARY KEY (seq);


--
-- Name: audit audit_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit
    ADD CONSTRAINT audit_id_key UNIQUE (id);


--
-- Name: audit audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit
    ADD CONSTRAINT audit_pkey PRIMARY KEY (seq);


--
-- Name: bookings bookings_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_id_key UNIQUE (id);


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (seq);


--
-- Name: catalog_changes catalog_changes_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_changes
    ADD CONSTRAINT catalog_changes_id_key UNIQUE (id);


--
-- Name: catalog_changes catalog_changes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_changes
    ADD CONSTRAINT catalog_changes_pkey PRIMARY KEY (seq);


--
-- Name: checklist_items checklist_items_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_items
    ADD CONSTRAINT checklist_items_id_key UNIQUE (id);


--
-- Name: checklist_items checklist_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_items
    ADD CONSTRAINT checklist_items_pkey PRIMARY KEY (seq);


--
-- Name: choice_groups choice_groups_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.choice_groups
    ADD CONSTRAINT choice_groups_id_key UNIQUE (id);


--
-- Name: choice_groups choice_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.choice_groups
    ADD CONSTRAINT choice_groups_pkey PRIMARY KEY (seq);


--
-- Name: confirmation confirmation_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.confirmation
    ADD CONSTRAINT confirmation_id_key UNIQUE (id);


--
-- Name: confirmation confirmation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.confirmation
    ADD CONSTRAINT confirmation_pkey PRIMARY KEY (seq);


--
-- Name: consumption_commands consumption_commands_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumption_commands
    ADD CONSTRAINT consumption_commands_id_key UNIQUE (id);


--
-- Name: consumption_commands consumption_commands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consumption_commands
    ADD CONSTRAINT consumption_commands_pkey PRIMARY KEY (seq);


--
-- Name: customers customers_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_id_key UNIQUE (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (seq);


--
-- Name: employees employees_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_id_key UNIQUE (id);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (seq);


--
-- Name: error_groups error_groups_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_groups
    ADD CONSTRAINT error_groups_id_key UNIQUE (id);


--
-- Name: error_groups error_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_groups
    ADD CONSTRAINT error_groups_pkey PRIMARY KEY (seq);


--
-- Name: error_occurrences error_occurrences_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_occurrences
    ADD CONSTRAINT error_occurrences_id_key UNIQUE (id);


--
-- Name: error_occurrences error_occurrences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_occurrences
    ADD CONSTRAINT error_occurrences_pkey PRIMARY KEY (seq);


--
-- Name: fake_accounting_calls fake_accounting_calls_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fake_accounting_calls
    ADD CONSTRAINT fake_accounting_calls_id_key UNIQUE (id);


--
-- Name: fake_accounting_calls fake_accounting_calls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fake_accounting_calls
    ADD CONSTRAINT fake_accounting_calls_pkey PRIMARY KEY (seq);


--
-- Name: henvendelser henvendelser_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.henvendelser
    ADD CONSTRAINT henvendelser_id_key UNIQUE (id);


--
-- Name: henvendelser henvendelser_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.henvendelser
    ADD CONSTRAINT henvendelser_pkey PRIMARY KEY (seq);


--
-- Name: inventory_movements inventory_movements_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_id_key UNIQUE (id);


--
-- Name: inventory_movements inventory_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_pkey PRIMARY KEY (seq);


--
-- Name: job_processes job_processes_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_processes
    ADD CONSTRAINT job_processes_id_key UNIQUE (id);


--
-- Name: job_processes job_processes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_processes
    ADD CONSTRAINT job_processes_pkey PRIMARY KEY (seq);


--
-- Name: job_schedules job_schedules_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_schedules
    ADD CONSTRAINT job_schedules_id_key UNIQUE (id);


--
-- Name: job_schedules job_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_schedules
    ADD CONSTRAINT job_schedules_pkey PRIMARY KEY (seq);


--
-- Name: jobs jobs_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_id_key UNIQUE (id);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (seq);


--
-- Name: mails mails_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mails
    ADD CONSTRAINT mails_id_key UNIQUE (id);


--
-- Name: mails mails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mails
    ADD CONSTRAINT mails_pkey PRIMARY KEY (seq);


--
-- Name: notifications notifications_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_id_key UNIQUE (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (seq);


--
-- Name: orders orders_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_id_key UNIQUE (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (seq);


--
-- Name: plan_impact_queue plan_impact_queue_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_impact_queue
    ADD CONSTRAINT plan_impact_queue_id_key UNIQUE (id);


--
-- Name: plan_impact_queue plan_impact_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_impact_queue
    ADD CONSTRAINT plan_impact_queue_pkey PRIMARY KEY (seq);


--
-- Name: plan_impacts plan_impacts_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_impacts
    ADD CONSTRAINT plan_impacts_id_key UNIQUE (id);


--
-- Name: plan_impacts plan_impacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_impacts
    ADD CONSTRAINT plan_impacts_pkey PRIMARY KEY (seq);


--
-- Name: plans plans_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_id_key UNIQUE (id);


--
-- Name: plans plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (seq);


--
-- Name: products products_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_id_key UNIQUE (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (seq);


--
-- Name: push_subscriptions push_subscriptions_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_id_key UNIQUE (id);


--
-- Name: push_subscriptions push_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (seq);


--
-- Name: quotes quotes_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT quotes_id_key UNIQUE (id);


--
-- Name: quotes quotes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT quotes_pkey PRIMARY KEY (seq);


--
-- Name: receipt receipt_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receipt
    ADD CONSTRAINT receipt_id_key UNIQUE (id);


--
-- Name: receipt receipt_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.receipt
    ADD CONSTRAINT receipt_pkey PRIMARY KEY (seq);


--
-- Name: recipes recipes_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipes
    ADD CONSTRAINT recipes_id_key UNIQUE (id);


--
-- Name: recipes recipes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recipes
    ADD CONSTRAINT recipes_pkey PRIMARY KEY (seq);


--
-- Name: reservations reservations_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_id_key UNIQUE (id);


--
-- Name: reservations reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reservations
    ADD CONSTRAINT reservations_pkey PRIMARY KEY (seq);


--
-- Name: reviews reviews_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_id_key UNIQUE (id);


--
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (seq);


--
-- Name: saved_queries saved_queries_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_queries
    ADD CONSTRAINT saved_queries_id_key UNIQUE (id);


--
-- Name: saved_queries saved_queries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_queries
    ADD CONSTRAINT saved_queries_pkey PRIMARY KEY (seq);


--
-- Name: schema_history schema_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_history
    ADD CONSTRAINT schema_history_pkey PRIMARY KEY (seq);


--
-- Name: sessions sessions_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_id_key UNIQUE (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (seq);


--
-- Name: setting setting_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.setting
    ADD CONSTRAINT setting_id_key UNIQUE (id);


--
-- Name: setting setting_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.setting
    ADD CONSTRAINT setting_pkey PRIMARY KEY (seq);


--
-- Name: sign_in_attempts sign_in_attempts_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sign_in_attempts
    ADD CONSTRAINT sign_in_attempts_id_key UNIQUE (id);


--
-- Name: sign_in_attempts sign_in_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sign_in_attempts
    ADD CONSTRAINT sign_in_attempts_pkey PRIMARY KEY (seq);


--
-- Name: stock_levels stock_levels_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT stock_levels_id_key UNIQUE (id);


--
-- Name: stock_levels stock_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT stock_levels_pkey PRIMARY KEY (seq);


--
-- Name: transfers transfers_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_id_key UNIQUE (id);


--
-- Name: transfers transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_pkey PRIMARY KEY (seq);


--
-- Name: unavailabilities unavailabilities_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unavailabilities
    ADD CONSTRAINT unavailabilities_id_key UNIQUE (id);


--
-- Name: unavailabilities unavailabilities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unavailabilities
    ADD CONSTRAINT unavailabilities_pkey PRIMARY KEY (seq);


--
-- Name: work_sessions work_sessions_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_sessions
    ADD CONSTRAINT work_sessions_id_key UNIQUE (id);


--
-- Name: work_sessions work_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_sessions
    ADD CONSTRAINT work_sessions_pkey PRIMARY KEY (seq);


--
-- Name: workflows workflows_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflows
    ADD CONSTRAINT workflows_id_key UNIQUE (id);


--
-- Name: workflows workflows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflows
    ADD CONSTRAINT workflows_pkey PRIMARY KEY (seq);


--
-- Name: idx_access_tokens_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_access_tokens_account_id ON public.access_tokens USING btree (account_id);


--
-- Name: idx_account_identities_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_account_identities_account_id ON public.account_identities USING btree (account_id);


--
-- Name: idx_articles_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_articles_department ON public.articles USING btree (department);


--
-- Name: idx_articles_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_articles_product_id ON public.articles USING btree (product_id);


--
-- Name: idx_assignment_overrides_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assignment_overrides_order_id ON public.assignment_overrides USING btree (order_id);


--
-- Name: idx_assignments_employee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assignments_employee_id ON public.assignments USING btree (employee_id);


--
-- Name: idx_assignments_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assignments_order_id ON public.assignments USING btree (order_id);


--
-- Name: idx_attachments_entity_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attachments_entity_record_id ON public.attachments USING btree (entity, record_id);


--
-- Name: idx_audit_entity_type_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_entity_type_entity_id ON public.audit USING btree (entity_type, entity_id);


--
-- Name: idx_bookings_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_order_id ON public.bookings USING btree (order_id);


--
-- Name: idx_bookings_product_id_from_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_product_id_from_date ON public.bookings USING btree (product_id, from_date);


--
-- Name: idx_checklist_items_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklist_items_order_id ON public.checklist_items USING btree (order_id);


--
-- Name: idx_employees_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_department ON public.employees USING btree (department);


--
-- Name: idx_error_groups_status_last_seen_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_groups_status_last_seen_at ON public.error_groups USING btree (status, last_seen_at);


--
-- Name: idx_error_occurrences_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_occurrences_group_id ON public.error_occurrences USING btree (group_id);


--
-- Name: idx_fake_accounting_calls_intent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fake_accounting_calls_intent_id ON public.fake_accounting_calls USING btree (intent_id);


--
-- Name: idx_fake_accounting_calls_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fake_accounting_calls_invoice_id ON public.fake_accounting_calls USING btree (invoice_id);


--
-- Name: idx_henvendelser_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_henvendelser_customer_id ON public.henvendelser USING btree (customer_id);


--
-- Name: idx_henvendelser_message_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_henvendelser_message_ref ON public.henvendelser USING btree (message_ref);


--
-- Name: idx_henvendelser_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_henvendelser_order_id ON public.henvendelser USING btree (order_id);


--
-- Name: idx_inventory_movements_article_id_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_article_id_revision ON public.inventory_movements USING btree (article_id, revision);


--
-- Name: idx_inventory_movements_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_order_id ON public.inventory_movements USING btree (order_id);


--
-- Name: idx_inventory_movements_product_id_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_product_id_revision ON public.inventory_movements USING btree (product_id, revision);


--
-- Name: idx_jobs_claimed_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jobs_claimed_by ON public.jobs USING btree (claimed_by);


--
-- Name: idx_jobs_kind_unique_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jobs_kind_unique_key ON public.jobs USING btree (kind, unique_key);


--
-- Name: idx_jobs_state_queue_due_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jobs_state_queue_due_at ON public.jobs USING btree (state, queue, due_at);


--
-- Name: idx_mails_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mails_key ON public.mails USING btree (key);


--
-- Name: idx_mails_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mails_status ON public.mails USING btree (status);


--
-- Name: idx_mails_to; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mails_to ON public.mails USING btree ("to");


--
-- Name: idx_notifications_recipient; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_recipient ON public.notifications USING btree (recipient);


--
-- Name: idx_orders_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_customer_id ON public.orders USING btree (customer_id);


--
-- Name: idx_orders_event_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_event_date ON public.orders USING btree (event_date);


--
-- Name: idx_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_status ON public.orders USING btree (status);


--
-- Name: idx_plan_impact_queue_catalog_change_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plan_impact_queue_catalog_change_id ON public.plan_impact_queue USING btree (catalog_change_id);


--
-- Name: idx_plan_impacts_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plan_impacts_order_id ON public.plan_impacts USING btree (order_id);


--
-- Name: idx_plans_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plans_order_id ON public.plans USING btree (order_id);


--
-- Name: idx_products_article_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_article_id ON public.products USING btree (article_id);


--
-- Name: idx_products_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_kind ON public.products USING btree (kind);


--
-- Name: idx_push_subscriptions_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_push_subscriptions_account ON public.push_subscriptions USING btree (account);


--
-- Name: idx_push_subscriptions_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_push_subscriptions_session ON public.push_subscriptions USING btree (session);


--
-- Name: idx_quotes_access_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_quotes_access_code ON public.quotes USING btree (access_code);


--
-- Name: idx_reservations_article_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reservations_article_id ON public.reservations USING btree (article_id);


--
-- Name: idx_reservations_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reservations_order_id ON public.reservations USING btree (order_id);


--
-- Name: idx_reviews_proposal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_proposal_id ON public.reviews USING btree (proposal_id);


--
-- Name: idx_reviews_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_status ON public.reviews USING btree (status);


--
-- Name: idx_reviews_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_subject_id ON public.reviews USING btree (subject_id);


--
-- Name: idx_sessions_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sessions_account_id ON public.sessions USING btree (account_id);


--
-- Name: idx_transfers_target_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transfers_target_id ON public.transfers USING btree (target_id);


--
-- Name: idx_unavailabilities_employee_id_start_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_unavailabilities_employee_id_start_date ON public.unavailabilities USING btree (employee_id, start_date);


--
-- Name: idx_work_sessions_employee_id_ended_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_sessions_employee_id_ended_at ON public.work_sessions USING btree (employee_id, ended_at);


--
-- Name: idx_work_sessions_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_sessions_order_id ON public.work_sessions USING btree (order_id);


--
-- Name: idx_workflows_kind_key_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflows_kind_key_status ON public.workflows USING btree (kind, key, status);


--
-- Name: idx_workflows_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflows_order_id ON public.workflows USING btree (order_id);


--
-- Name: idx_workflows_status_due_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workflows_status_due_at ON public.workflows USING btree (status, due_at);


--
-- Name: uq_access_tokens_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_access_tokens_token_hash ON public.access_tokens USING btree (token_hash);


--
-- Name: uq_account_identities_account_id_strategy; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_account_identities_account_id_strategy ON public.account_identities USING btree (account_id, strategy);


--
-- Name: uq_account_identities_strategy_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_account_identities_strategy_subject ON public.account_identities USING btree (strategy, subject);


--
-- Name: uq_accounts_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_accounts_email ON public.accounts USING btree (email);


--
-- Name: uq_accounts_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_accounts_name ON public.accounts USING btree (name);


--
-- Name: uq_confirmation_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_confirmation_token_hash ON public.confirmation USING btree (token_hash);


--
-- Name: uq_consumption_commands_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_consumption_commands_order_id ON public.consumption_commands USING btree (order_id);


--
-- Name: uq_employees_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_employees_actor ON public.employees USING btree (actor);


--
-- Name: uq_error_groups_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_error_groups_fingerprint ON public.error_groups USING btree (fingerprint);


--
-- Name: uq_job_schedules_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_job_schedules_name ON public.job_schedules USING btree (name);


--
-- Name: uq_notifications_type_event_id_recipient; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_notifications_type_event_id_recipient ON public.notifications USING btree (type, event_id, recipient);


--
-- Name: uq_push_subscriptions_endpoint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_push_subscriptions_endpoint ON public.push_subscriptions USING btree (endpoint);


--
-- Name: uq_quotes_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_quotes_order_id ON public.quotes USING btree (order_id);


--
-- Name: uq_receipt_actor_tool_request_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_receipt_actor_tool_request_key ON public.receipt USING btree (actor, tool, request_key);


--
-- Name: uq_reviews_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_reviews_idempotency_key ON public.reviews USING btree (idempotency_key);


--
-- Name: uq_saved_queries_account_page; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_saved_queries_account_page ON public.saved_queries USING btree (account, page);


--
-- Name: uq_sessions_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_sessions_token_hash ON public.sessions USING btree (token_hash);


--
-- Name: uq_setting_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_setting_key ON public.setting USING btree (key);


--
-- Name: uq_sign_in_attempts_state_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_sign_in_attempts_state_hash ON public.sign_in_attempts USING btree (state_hash);


--
-- Name: uq_stock_levels_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_stock_levels_product_id ON public.stock_levels USING btree (product_id);


--
-- PostgreSQL database dump complete
--

\unrestrict ViplJYeqRmW4mhkfMtWAEtWyQ0VW7DJ2gUGKuWlvXLabxtJc3xCbDxVm0hE62Vu

