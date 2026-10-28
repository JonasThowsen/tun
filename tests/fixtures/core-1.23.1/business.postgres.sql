--
-- PostgreSQL database dump
--

\restrict QbNhOTOHkrmvS9vDoxS8QRhNgZdaoihRiBn8n37NQM5COq0djxOO5RoJxs3yRYC

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

INSERT INTO public.accounts OVERRIDING SYSTEM VALUE VALUES (1, 'acc_bf7wjqvcwmr4wc9m', 'ada', NULL, 'person', 'admin', 'ada@example.no', 'active', '2026-03-01T09:00:00Z', 'admin:ada', NULL);


--
-- Data for Name: attachment_contents; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: attachments; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: audit; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (1, 'aud_7cw45jg4d8am03bj', '2026-03-01T09:00:00Z', 'admin:ada', 'accounts_create', 'ok', 'account', 'acc_bf7wjqvcwmr4wc9m', NULL, NULL, 'req_48ef1m272qq0ekat', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (2, 'aud_pqfj5jy19bj9dam1', '2026-03-01T09:00:00Z', 'admin:ada', 'settings_set', 'ok', 'setting', 'lenker.base_url', NULL, NULL, 'req_7amz49fjnppgaz5d', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (3, 'aud_bxnvy3smj9s51xgt', '2026-03-01T09:00:00Z', 'admin:ada', 'settings_set', 'ok', 'setting', NULL, NULL, NULL, 'req_7amz49fjnppgaz5d', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (4, 'aud_wpqesm5g8zrzk1tk', '2026-03-01T09:00:00Z', 'admin:ada', 'debug_schedule', 'ok', 'workflow', 'wf_jc1w5h8h3vgg2djr', NULL, NULL, 'req_a0cy8p265c80sghp', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (5, 'aud_k017sf4dfs9c6ycy', '2026-03-01T09:00:00Z', 'admin:ada', 'debug_schedule', 'ok', 'workflow', 'wf_bpv5aabgkqzw2t2q', NULL, NULL, 'req_dte6xngmrx2amp76', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (6, 'aud_66zwdf4e0kea6006', '2026-03-01T09:00:00Z', 'admin:ada', 'debug_schedule', 'ok', 'workflow', 'wf_tqz8rtta0x75xdrg', NULL, NULL, 'req_zm3ek95kztyb8s8b', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (7, 'aud_aw7tggqgfgmmmma3', '2026-03-01T09:00:00Z', 'admin:ada', 'debug_schedule', 'ok', 'workflow', 'wf_dpm22mnhxsg3v9zm', NULL, NULL, 'req_hk9p3n50r3qydj26', NULL, NULL);
INSERT INTO public.audit OVERRIDING SYSTEM VALUE VALUES (8, 'aud_xydx0xdbtrqj70tj', '2026-03-01T09:00:00Z', 'admin:ada', 'customers_create', 'ok', 'customer', 'cus_pdgp3axkx5m6j5he', NULL, NULL, 'req_3q6ky1ekrbfz8dc4', NULL, NULL);


--
-- Data for Name: confirmation; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.customers OVERRIDING SYSTEM VALUE VALUES (1, 'cus_pdgp3axkx5m6j5he', 0, NULL, NULL, 0, NULL, 1, 'Kari Nordmann', 'kari@example.no', NULL, NULL, 0, '2026-03-01T09:00:00Z');


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
-- Data for Name: job_processes; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: job_schedules; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.job_schedules OVERRIDING SYSTEM VALUE VALUES (1, 'jsc_7smcwf3g6kxmamy1', 'attachments_sweep', '2026-03-01T09:00:00Z', '2026-03-01T03:30', '2026-03-01T02:30:00Z', NULL, NULL);


--
-- Data for Name: jobs; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.jobs OVERRIDING SYSTEM VALUE VALUES (1, 'job_ka1yf0239eajq7p3', 'run_workflow', 'workflows', '{"workflow_id":"wf_jc1w5h8h3vgg2djr"}', 'queued', 0, '2026-03-01T10:00:00Z', 0, 3, 0, '492902374dc9acb2f3ffd814eca715a2a51a85e5b7950e863189fed0be606432', '2026-03-01T09:00:00Z', 'admin:ada', NULL, NULL, NULL, NULL, '[]', NULL);
INSERT INTO public.jobs OVERRIDING SYSTEM VALUE VALUES (2, 'job_4fzwgfgf7bped1fv', 'run_workflow', 'workflows', '{"workflow_id":"wf_bpv5aabgkqzw2t2q"}', 'queued', 0, '2026-03-01T11:00:00Z', 0, 3, 0, 'bb79be956eac2f28b87a55eda2e01b36eb22d4d45e760ad87ee16e34ac341735', '2026-03-01T09:00:00Z', 'admin:ada', NULL, NULL, NULL, NULL, '[]', NULL);
INSERT INTO public.jobs OVERRIDING SYSTEM VALUE VALUES (3, 'job_a62kka6wrs9weda2', 'run_workflow', 'workflows', '{"workflow_id":"wf_tqz8rtta0x75xdrg"}', 'queued', 0, '2026-03-01T12:00:00Z', 0, 3, 0, '075ecf7a1b96e53d60dcc54ab3aa4f4fa2dde77a37a83e71ee831aaa96835dcd', '2026-03-01T09:00:00Z', 'admin:ada', NULL, NULL, NULL, NULL, '[]', NULL);
INSERT INTO public.jobs OVERRIDING SYSTEM VALUE VALUES (4, 'job_tecrnjn0ew0pf60e', 'run_workflow', 'workflows', '{"workflow_id":"wf_dpm22mnhxsg3v9zm"}', 'queued', 0, '2026-03-01T13:00:00Z', 0, 3, 0, 'd0a5ab6bfbead99bddad573e673f8cf6d052c2479be67554da731a171c2bd857', '2026-03-01T09:00:00Z', 'admin:ada', NULL, NULL, NULL, NULL, '[]', NULL);
INSERT INTO public.jobs OVERRIDING SYSTEM VALUE VALUES (5, 'job_yt7mrcm9abqnhjcg', 'send_queued_mail', 'mail', '{"mail_id":"mail_xwn0dx45bae9asmr"}', 'queued', 0, '2026-03-01T09:00:00Z', 0, 7, 0, 'c4964e911395c6343396945790f29b7265018a70a5c526566652bbe9a3cfcd7b', '2026-03-01T09:00:00Z', 'system', NULL, NULL, NULL, NULL, '[]', NULL);


--
-- Data for Name: mails; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.mails OVERRIDING SYSTEM VALUE VALUES (1, 'mail_xwn0dx45bae9asmr', 'kari@example.no', 'Hei', 'Velkommen', NULL, NULL, NULL, 'queued', 0, 'job_yt7mrcm9abqnhjcg', NULL, NULL, NULL, '2026-03-01T09:00:00Z', NULL);


--
-- Data for Name: push_subscriptions; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: receipt; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: saved_queries; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: schema_history; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (1, 'core major 1 opened this database', '2026-10-28T06:25:44Z', 'tun-core', 'core-major-1');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (2, 'CREATE TABLE "attachment_contents" ("id" TEXT COLLATE "C" PRIMARY KEY,
                                         "content" BYTEA NOT NULL)', '2026-10-28T06:25:44Z', 'core', 'core_0001_create_attachment_contents');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (3, 'CREATE TABLE "audit" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "at" TEXT COLLATE "C", "actor" TEXT COLLATE "C", "tool" TEXT COLLATE "C", "outcome" TEXT COLLATE "C", "entity_type" TEXT COLLATE "C", "entity_id" TEXT COLLATE "C", "request_key" TEXT COLLATE "C", "error_code" TEXT COLLATE "C", "request_id" TEXT COLLATE "C", "reason" TEXT COLLATE "C", "credential" TEXT COLLATE "C")', '2026-10-28T06:25:44Z', 'core', 'core_0002_create_audit');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (4, 'CREATE TABLE "receipt" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "actor" TEXT COLLATE "C", "tool" TEXT COLLATE "C", "request_key" TEXT COLLATE "C", "input_hash" TEXT COLLATE "C", "redacted" BIGINT, "result" TEXT COLLATE "C", "created_at" TEXT COLLATE "C")', '2026-10-28T06:25:44Z', 'core', 'core_0003_create_receipt');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (5, 'CREATE TABLE "confirmation" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "token_hash" TEXT COLLATE "C", "actor" TEXT COLLATE "C", "tool" TEXT COLLATE "C", "input_hash" TEXT COLLATE "C", "expires_at" TEXT COLLATE "C", "request_id" TEXT COLLATE "C", "used_at" TEXT COLLATE "C", "created_at" TEXT COLLATE "C")', '2026-10-28T06:25:44Z', 'core', 'core_0004_create_confirmation');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (6, 'CREATE TABLE "setting" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "key" TEXT COLLATE "C", "value" TEXT COLLATE "C")', '2026-10-28T06:25:44Z', 'core', 'core_0005_create_setting');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (7, 'CREATE TABLE "fake_accounting_calls" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "intent_id" TEXT COLLATE "C", "invoice_id" TEXT COLLATE "C", "external_ref" TEXT COLLATE "C", "total_ore" BIGINT, "at" TEXT COLLATE "C")', '2026-10-28T06:25:44Z', 'core', 'core_0006_create_fake_accounting_calls');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (8, 'CREATE TABLE "jobs" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "kind" TEXT COLLATE "C", "queue" TEXT COLLATE "C", "arguments" TEXT COLLATE "C", "state" TEXT COLLATE "C" DEFAULT ''queued'', "priority" BIGINT DEFAULT 0, "due_at" TEXT COLLATE "C", "attempts" BIGINT DEFAULT 0, "max_attempts" BIGINT, "snoozes" BIGINT DEFAULT 0, "unique_key" TEXT COLLATE "C", "enqueued_at" TEXT COLLATE "C", "enqueued_by" TEXT COLLATE "C", "claimed_by" TEXT COLLATE "C", "started_at" TEXT COLLATE "C", "finished_at" TEXT COLLATE "C", "last_error" TEXT COLLATE "C", "errors" TEXT COLLATE "C", "note" TEXT COLLATE "C")', '2026-10-28T06:25:44Z', 'core', 'core_0007_create_jobs');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (9, 'CREATE TABLE "job_schedules" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "name" TEXT COLLATE "C", "first_seen_at" TEXT COLLATE "C", "last_occurrence" TEXT COLLATE "C", "last_occurrence_at" TEXT COLLATE "C", "last_job_id" TEXT COLLATE "C", "last_enqueued" BIGINT)', '2026-10-28T06:25:44Z', 'core', 'core_0008_create_job_schedules');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (10, 'CREATE TABLE "job_processes" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "started_at" TEXT COLLATE "C", "lock_key" BIGINT)', '2026-10-28T06:25:44Z', 'core', 'core_0009_create_job_processes');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (11, 'CREATE TABLE "mails" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "to" TEXT COLLATE "C", "subject" TEXT COLLATE "C", "text" TEXT COLLATE "C", "html" TEXT COLLATE "C", "reply_to" TEXT COLLATE "C", "key" TEXT COLLATE "C", "status" TEXT COLLATE "C" DEFAULT ''queued'', "attempts" BIGINT DEFAULT 0, "job_id" TEXT COLLATE "C", "last_error" TEXT COLLATE "C", "provider" TEXT COLLATE "C", "provider_id" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "sent_at" TEXT COLLATE "C")', '2026-10-28T06:25:44Z', 'core', 'core_0010_create_mails');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (12, 'CREATE TABLE "attachments" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "entity" TEXT COLLATE "C", "record_id" TEXT COLLATE "C", "filename" TEXT COLLATE "C", "content_type" TEXT COLLATE "C", "size" BIGINT, "width" BIGINT, "height" BIGINT, "sha256" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "created_by" TEXT COLLATE "C", "account" TEXT COLLATE "C")', '2026-10-28T06:25:44Z', 'core', 'core_0011_create_attachments');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (13, 'CREATE TABLE "workflows" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "key" TEXT COLLATE "C", "request_id" TEXT COLLATE "C", "kind" TEXT COLLATE "C", "order_id" TEXT COLLATE "C", "customer_id" TEXT COLLATE "C", "due_at" TEXT COLLATE "C", "status" TEXT COLLATE "C" DEFAULT ''planlagt'', "executed_at" TEXT COLLATE "C", "note" TEXT COLLATE "C", "subject_id" TEXT COLLATE "C")', '2026-10-28T06:25:44Z', 'core', 'core_0012_create_workflows');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (14, 'CREATE TABLE "error_groups" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "fingerprint" TEXT COLLATE "C", "code" TEXT COLLATE "C", "error_type" TEXT COLLATE "C", "message" TEXT COLLATE "C", "tool" TEXT COLLATE "C", "backtrace" TEXT COLLATE "C", "request_id" TEXT COLLATE "C", "first_seen_at" TEXT COLLATE "C", "last_seen_at" TEXT COLLATE "C", "count" BIGINT DEFAULT 0, "status" TEXT COLLATE "C" DEFAULT ''open'', "status_changed_at" TEXT COLLATE "C", "status_changed_by" TEXT COLLATE "C", "notified_at" TEXT COLLATE "C")', '2026-10-28T06:25:45Z', 'core', 'core_0013_create_error_groups');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (15, 'CREATE TABLE "error_occurrences" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "group_id" TEXT COLLATE "C", "at" TEXT COLLATE "C", "request_id" TEXT COLLATE "C", "kind" TEXT COLLATE "C", "tool" TEXT COLLATE "C", "actor" TEXT COLLATE "C", "message" TEXT COLLATE "C", "total_ms" TEXT COLLATE "C")', '2026-10-28T06:25:45Z', 'core', 'core_0014_create_error_occurrences');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (16, 'CREATE TABLE "accounts" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "name" TEXT COLLATE "C", "display_name" TEXT COLLATE "C", "kind" TEXT COLLATE "C", "role" TEXT COLLATE "C", "email" TEXT COLLATE "C", "status" TEXT COLLATE "C" DEFAULT ''active'', "created_at" TEXT COLLATE "C", "created_by" TEXT COLLATE "C", "invited_at" TEXT COLLATE "C")', '2026-10-28T06:25:45Z', 'core', 'core_0015_create_accounts');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (17, 'CREATE TABLE "access_tokens" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "account_id" TEXT COLLATE "C", "label" TEXT COLLATE "C", "role" TEXT COLLATE "C", "prefix" TEXT COLLATE "C", "token_hash" TEXT COLLATE "C", "expires_at" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "created_by" TEXT COLLATE "C", "last_used_at" TEXT COLLATE "C", "revoked_at" TEXT COLLATE "C")', '2026-10-28T06:25:45Z', 'core', 'core_0016_create_access_tokens');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (18, 'CREATE TABLE "sessions" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "account_id" TEXT COLLATE "C", "token_hash" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "last_seen_at" TEXT COLLATE "C")', '2026-10-28T06:25:45Z', 'core', 'core_0017_create_sessions');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (19, 'CREATE TABLE "account_identities" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "account_id" TEXT COLLATE "C", "strategy" TEXT COLLATE "C", "issuer" TEXT COLLATE "C", "subject" TEXT COLLATE "C", "email" TEXT COLLATE "C", "linked_at" TEXT COLLATE "C", "last_used_at" TEXT COLLATE "C")', '2026-10-28T06:25:45Z', 'core', 'core_0018_create_account_identities');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (20, 'CREATE TABLE "sign_in_attempts" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "strategy" TEXT COLLATE "C", "state_hash" TEXT COLLATE "C", "nonce" TEXT COLLATE "C", "verifier" TEXT COLLATE "C", "purpose" TEXT COLLATE "C", "setup_hash" TEXT COLLATE "C", "account_name" TEXT COLLATE "C", "display_name" TEXT COLLATE "C", "expires_at" TEXT COLLATE "C")', '2026-10-28T06:25:45Z', 'core', 'core_0019_create_sign_in_attempts');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (21, 'CREATE TABLE "push_subscriptions" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "account" TEXT COLLATE "C", "endpoint" TEXT COLLATE "C", "p256dh" TEXT COLLATE "C", "auth" TEXT COLLATE "C", "server_key" TEXT COLLATE "C", "session" TEXT COLLATE "C", "device" TEXT COLLATE "C", "created_at" TEXT COLLATE "C", "tested_at" TEXT COLLATE "C")', '2026-10-28T06:25:45Z', 'core', 'core_0020_create_push_subscriptions');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (22, 'CREATE TABLE "saved_queries" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "account" TEXT COLLATE "C", "page" TEXT COLLATE "C", "query" TEXT COLLATE "C")', '2026-10-28T06:25:45Z', 'core', 'core_0021_create_saved_queries');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (23, 'CREATE TABLE "customers" ("seq" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, "id" TEXT COLLATE "C" NOT NULL UNIQUE, "marketing_consent" BIGINT, "consent_source" TEXT COLLATE "C", "consent_at" TEXT COLLATE "C", "erased" BIGINT, "erased_at" TEXT COLLATE "C", "revision" BIGINT DEFAULT 1, "name" TEXT COLLATE "C", "email" TEXT COLLATE "C", "phone" TEXT COLLATE "C", "notes" TEXT COLLATE "C", "completed_orders" BIGINT DEFAULT 0, "created_at" TEXT COLLATE "C")', '2026-10-28T06:25:45Z', 'customers', 'customers_0001_create_customers');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (24, 'CREATE INDEX "idx_audit_entity_type_entity_id" ON "audit" ("entity_type", "entity_id")', '2026-10-28T06:25:45Z', 'core', 'core_0022_idx_audit_entity_type_entity_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (25, 'CREATE INDEX "idx_fake_accounting_calls_intent_id" ON "fake_accounting_calls" ("intent_id")', '2026-10-28T06:25:45Z', 'core', 'core_0023_idx_fake_accounting_calls_intent_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (26, 'CREATE INDEX "idx_fake_accounting_calls_invoice_id" ON "fake_accounting_calls" ("invoice_id")', '2026-10-28T06:25:45Z', 'core', 'core_0024_idx_fake_accounting_calls_invoice_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (27, 'CREATE INDEX "idx_jobs_state_queue_due_at" ON "jobs" ("state", "queue", "due_at")', '2026-10-28T06:25:45Z', 'core', 'core_0025_idx_jobs_state_queue_due_at');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (28, 'CREATE INDEX "idx_jobs_kind_unique_key" ON "jobs" ("kind", "unique_key")', '2026-10-28T06:25:45Z', 'core', 'core_0026_idx_jobs_kind_unique_key');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (29, 'CREATE INDEX "idx_jobs_claimed_by" ON "jobs" ("claimed_by")', '2026-10-28T06:25:45Z', 'core', 'core_0027_idx_jobs_claimed_by');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (30, 'CREATE INDEX "idx_mails_status" ON "mails" ("status")', '2026-10-28T06:25:45Z', 'core', 'core_0028_idx_mails_status');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (31, 'CREATE INDEX "idx_mails_key" ON "mails" ("key")', '2026-10-28T06:25:45Z', 'core', 'core_0029_idx_mails_key');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (32, 'CREATE INDEX "idx_mails_to" ON "mails" ("to")', '2026-10-28T06:25:45Z', 'core', 'core_0030_idx_mails_to');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (33, 'CREATE INDEX "idx_attachments_entity_record_id" ON "attachments" ("entity", "record_id")', '2026-10-28T06:25:45Z', 'core', 'core_0031_idx_attachments_entity_record_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (34, 'CREATE INDEX "idx_workflows_order_id" ON "workflows" ("order_id")', '2026-10-28T06:25:45Z', 'core', 'core_0032_idx_workflows_order_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (35, 'CREATE INDEX "idx_workflows_status_due_at" ON "workflows" ("status", "due_at")', '2026-10-28T06:25:45Z', 'core', 'core_0033_idx_workflows_status_due_at');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (36, 'CREATE INDEX "idx_workflows_kind_key_status" ON "workflows" ("kind", "key", "status")', '2026-10-28T06:25:45Z', 'core', 'core_0034_idx_workflows_kind_key_status');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (37, 'CREATE INDEX "idx_error_groups_status_last_seen_at" ON "error_groups" ("status", "last_seen_at")', '2026-10-28T06:25:45Z', 'core', 'core_0035_idx_error_groups_status_last_seen_at');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (38, 'CREATE INDEX "idx_error_occurrences_group_id" ON "error_occurrences" ("group_id")', '2026-10-28T06:25:45Z', 'core', 'core_0036_idx_error_occurrences_group_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (39, 'CREATE INDEX "idx_access_tokens_account_id" ON "access_tokens" ("account_id")', '2026-10-28T06:25:45Z', 'core', 'core_0037_idx_access_tokens_account_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (40, 'CREATE INDEX "idx_sessions_account_id" ON "sessions" ("account_id")', '2026-10-28T06:25:45Z', 'core', 'core_0038_idx_sessions_account_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (41, 'CREATE INDEX "idx_account_identities_account_id" ON "account_identities" ("account_id")', '2026-10-28T06:25:45Z', 'core', 'core_0039_idx_account_identities_account_id');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (42, 'CREATE INDEX "idx_push_subscriptions_account" ON "push_subscriptions" ("account")', '2026-10-28T06:25:45Z', 'core', 'core_0040_idx_push_subscriptions_account');
INSERT INTO public.schema_history OVERRIDING SYSTEM VALUE VALUES (43, 'CREATE INDEX "idx_push_subscriptions_session" ON "push_subscriptions" ("session")', '2026-10-28T06:25:45Z', 'core', 'core_0041_idx_push_subscriptions_session');


--
-- Data for Name: sessions; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: setting; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.setting OVERRIDING SYSTEM VALUE VALUES (1, 'set_rpwckp91rjz3tyjn', 'lenker.hemmelighet', '"442b47a3e4f3b359d470e6c79e3e87d037653d4fb140f3d2f23e077a72561ec3"');
INSERT INTO public.setting OVERRIDING SYSTEM VALUE VALUES (2, 'set_2655q5sfh38shyt0', 'push.hemmelighet', '"79cd2faf196ce69b5e56efd81e64d756e7dc2b6785fc6b8199188989e0fdb7b9"');
INSERT INTO public.setting OVERRIDING SYSTEM VALUE VALUES (3, 'set_pk0hvxbks0qtp05k', 'lenker.base_url', '"https://tenant.example"');


--
-- Data for Name: sign_in_attempts; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: workflows; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.workflows OVERRIDING SYSTEM VALUE VALUES (1, 'wf_jc1w5h8h3vgg2djr', NULL, NULL, 'debug_ping', NULL, NULL, '2026-03-01T10:00:00Z', 'planlagt', NULL, NULL, NULL);
INSERT INTO public.workflows OVERRIDING SYSTEM VALUE VALUES (2, 'wf_bpv5aabgkqzw2t2q', NULL, NULL, 'debug_ping', NULL, NULL, '2026-03-01T11:00:00Z', 'utført', NULL, NULL, NULL);
INSERT INTO public.workflows OVERRIDING SYSTEM VALUE VALUES (3, 'wf_tqz8rtta0x75xdrg', NULL, NULL, 'debug_ping', NULL, NULL, '2026-03-01T12:00:00Z', 'avbrutt', NULL, NULL, NULL);
INSERT INTO public.workflows OVERRIDING SYSTEM VALUE VALUES (4, 'wf_dpm22mnhxsg3v9zm', NULL, NULL, 'debug_ping', NULL, NULL, '2026-03-01T13:00:00Z', 'feilet', NULL, NULL, NULL);


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
-- Name: attachments_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.attachments_seq_seq', 1, false);


--
-- Name: audit_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.audit_seq_seq', 8, true);


--
-- Name: confirmation_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.confirmation_seq_seq', 1, false);


--
-- Name: customers_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.customers_seq_seq', 1, true);


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
-- Name: push_subscriptions_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.push_subscriptions_seq_seq', 1, false);


--
-- Name: receipt_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.receipt_seq_seq', 1, false);


--
-- Name: saved_queries_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.saved_queries_seq_seq', 1, false);


--
-- Name: schema_history_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.schema_history_seq_seq', 43, true);


--
-- Name: sessions_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sessions_seq_seq', 1, false);


--
-- Name: setting_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.setting_seq_seq', 3, true);


--
-- Name: sign_in_attempts_seq_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sign_in_attempts_seq_seq', 1, false);


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
-- Name: idx_attachments_entity_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attachments_entity_record_id ON public.attachments USING btree (entity, record_id);


--
-- Name: idx_audit_entity_type_entity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_entity_type_entity_id ON public.audit USING btree (entity_type, entity_id);


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
-- Name: idx_push_subscriptions_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_push_subscriptions_account ON public.push_subscriptions USING btree (account);


--
-- Name: idx_push_subscriptions_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_push_subscriptions_session ON public.push_subscriptions USING btree (session);


--
-- Name: idx_sessions_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sessions_account_id ON public.sessions USING btree (account_id);


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
-- Name: uq_error_groups_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_error_groups_fingerprint ON public.error_groups USING btree (fingerprint);


--
-- Name: uq_job_schedules_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_job_schedules_name ON public.job_schedules USING btree (name);


--
-- Name: uq_push_subscriptions_endpoint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_push_subscriptions_endpoint ON public.push_subscriptions USING btree (endpoint);


--
-- Name: uq_receipt_actor_tool_request_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_receipt_actor_tool_request_key ON public.receipt USING btree (actor, tool, request_key);


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
-- PostgreSQL database dump complete
--

\unrestrict QbNhOTOHkrmvS9vDoxS8QRhNgZdaoihRiBn8n37NQM5COq0djxOO5RoJxs3yRYC

