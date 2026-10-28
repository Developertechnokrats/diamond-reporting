--
-- PostgreSQL database dump
--

\restrict JpW9bcjAeYrPE3echeE31JQgteFrFFP1CkkWod05TVUqtbSWw4hzvSApnHs3iNu

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.3

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

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Extensions required by the default-value functions below. On a fresh Supabase
-- project these already exist in the "extensions" schema; these statements make
-- a restore into plain Postgres succeed too. (Added during schema verification.)
--

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA extensions;


--
-- Name: recalculate_pct_time_to_hire(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recalculate_pct_time_to_hire(p_tracktik_post_id text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  total_days NUMERIC;
BEGIN
  -- Sum all closed cycles' days_to_hire
  SELECT COALESCE(SUM(days_to_hire), 0)
  INTO total_days
  FROM job_cycles
  WHERE tracktik_post_id = p_tracktik_post_id
    AND days_to_hire IS NOT NULL;

  -- Update pct for each cycle
  IF total_days > 0 THEN
    UPDATE job_cycles
    SET pct_time_to_hire = ROUND((days_to_hire / total_days) * 100, 2),
        updated_at = NOW()
    WHERE tracktik_post_id = p_tracktik_post_id
      AND days_to_hire IS NOT NULL;
  END IF;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: import_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_batches (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    filename text,
    imported_at timestamp with time zone DEFAULT now(),
    total_jobs integer,
    total_cycles integer,
    status text DEFAULT 'completed'::text,
    snapshot jsonb
);


--
-- Name: job_cycles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_cycles (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    tracktik_post_id text NOT NULL,
    cycle_number integer NOT NULL,
    opened_at timestamp with time zone,
    closed_at timestamp with time zone,
    days_to_hire numeric(10,2),
    pct_time_to_hire numeric(10,2),
    is_open boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    source character varying(10) DEFAULT 'ghl'::character varying
);


--
-- Name: job_requisitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_requisitions (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    tracktik_post_id text NOT NULL,
    ghl_id text,
    advertised_pay_rate text,
    applicant_radius text,
    applicant_stack_status text,
    city_of_site_location text,
    disqualifying_questions text,
    employment_status text,
    hiring_manager text,
    hr_approval_status text,
    in_person_interview_address text,
    industry text,
    interview_calendar text,
    interview_type text,
    job_duties text,
    officer_type text,
    other_preferences text,
    position_specific_requirements text,
    position_start_date text,
    position_status text,
    preferred_screening_questions text,
    region text,
    schedule text,
    serviceable_zip_code text,
    site_name_position_shift text,
    state_of_site_location text,
    tier1_zip_codes text,
    tier2_zip_codes text,
    tier3_zip_codes text,
    tracktik_site_id text,
    zip_code_of_site text,
    current_status text DEFAULT 'created'::text,
    total_cycles integer DEFAULT 0,
    first_seen_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    needs_review boolean DEFAULT false,
    review_notes text,
    hiring_needs integer
);


--
-- Name: job_status_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_status_history (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    tracktik_post_id text NOT NULL,
    status text NOT NULL,
    cycle_number integer,
    recorded_at timestamp with time zone DEFAULT now(),
    raw_payload jsonb
);


--
-- Name: manual_corrections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.manual_corrections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tracktik_post_id character varying(100) NOT NULL,
    correction_type character varying(50) NOT NULL,
    cycle_number integer,
    before_state jsonb,
    after_state jsonb,
    note text,
    corrected_by character varying(100) DEFAULT 'admin'::character varying,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: import_batches import_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT import_batches_pkey PRIMARY KEY (id);


--
-- Name: job_cycles job_cycles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_cycles
    ADD CONSTRAINT job_cycles_pkey PRIMARY KEY (id);


--
-- Name: job_cycles job_cycles_tracktik_post_id_cycle_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_cycles
    ADD CONSTRAINT job_cycles_tracktik_post_id_cycle_number_key UNIQUE (tracktik_post_id, cycle_number);


--
-- Name: job_requisitions job_requisitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisitions
    ADD CONSTRAINT job_requisitions_pkey PRIMARY KEY (id);


--
-- Name: job_requisitions job_requisitions_tracktik_post_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_requisitions
    ADD CONSTRAINT job_requisitions_tracktik_post_id_key UNIQUE (tracktik_post_id);


--
-- Name: job_status_history job_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_status_history
    ADD CONSTRAINT job_status_history_pkey PRIMARY KEY (id);


--
-- Name: manual_corrections manual_corrections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_corrections
    ADD CONSTRAINT manual_corrections_pkey PRIMARY KEY (id);


--
-- Name: idx_corrections_post_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_corrections_post_id ON public.manual_corrections USING btree (tracktik_post_id);


--
-- Name: idx_cycles_closed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cycles_closed ON public.job_cycles USING btree (closed_at);


--
-- Name: idx_cycles_is_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cycles_is_open ON public.job_cycles USING btree (is_open);


--
-- Name: idx_cycles_opened; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cycles_opened ON public.job_cycles USING btree (opened_at);


--
-- Name: idx_cycles_tracktik; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cycles_tracktik ON public.job_cycles USING btree (tracktik_post_id);


--
-- Name: idx_history_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_history_cycle ON public.job_status_history USING btree (cycle_number);


--
-- Name: idx_history_recorded; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_history_recorded ON public.job_status_history USING btree (recorded_at);


--
-- Name: idx_history_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_history_status ON public.job_status_history USING btree (status);


--
-- Name: idx_history_tracktik; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_history_tracktik ON public.job_status_history USING btree (tracktik_post_id);


--
-- Name: idx_import_batches_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_batches_date ON public.import_batches USING btree (imported_at);


--
-- Name: idx_import_batches_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_batches_status ON public.import_batches USING btree (status);


--
-- Name: idx_job_req_city; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_req_city ON public.job_requisitions USING btree (city_of_site_location);


--
-- Name: idx_job_req_manager; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_req_manager ON public.job_requisitions USING btree (hiring_manager);


--
-- Name: idx_job_req_needs_review; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_req_needs_review ON public.job_requisitions USING btree (needs_review);


--
-- Name: idx_job_req_region; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_req_region ON public.job_requisitions USING btree (region);


--
-- Name: idx_job_req_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_req_status ON public.job_requisitions USING btree (current_status);


--
-- Name: idx_job_req_tracktik; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_req_tracktik ON public.job_requisitions USING btree (tracktik_post_id);


--
-- Name: idx_job_req_updated; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_job_req_updated ON public.job_requisitions USING btree (updated_at);


--
-- Name: job_cycles job_cycles_tracktik_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_cycles
    ADD CONSTRAINT job_cycles_tracktik_post_id_fkey FOREIGN KEY (tracktik_post_id) REFERENCES public.job_requisitions(tracktik_post_id) ON DELETE CASCADE;


--
-- Name: job_status_history job_status_history_tracktik_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_status_history
    ADD CONSTRAINT job_status_history_tracktik_post_id_fkey FOREIGN KEY (tracktik_post_id) REFERENCES public.job_requisitions(tracktik_post_id) ON DELETE CASCADE;


--
-- Name: import_batches anon_read_import_batches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_read_import_batches ON public.import_batches FOR SELECT TO anon USING (true);


--
-- Name: job_cycles anon_read_job_cycles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_read_job_cycles ON public.job_cycles FOR SELECT TO anon USING (true);


--
-- Name: job_requisitions anon_read_job_requisitions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_read_job_requisitions ON public.job_requisitions FOR SELECT TO anon USING (true);


--
-- Name: job_status_history anon_read_job_status_history; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anon_read_job_status_history ON public.job_status_history FOR SELECT TO anon USING (true);


--
-- Name: import_batches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.import_batches ENABLE ROW LEVEL SECURITY;

--
-- Name: job_cycles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.job_cycles ENABLE ROW LEVEL SECURITY;

--
-- Name: job_requisitions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.job_requisitions ENABLE ROW LEVEL SECURITY;

--
-- Name: job_status_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.job_status_history ENABLE ROW LEVEL SECURITY;

--
-- Name: import_batches service_role_all_import_batches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY service_role_all_import_batches ON public.import_batches TO service_role USING (true) WITH CHECK (true);


--
-- Name: job_cycles service_role_all_job_cycles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY service_role_all_job_cycles ON public.job_cycles TO service_role USING (true) WITH CHECK (true);


--
-- Name: job_requisitions service_role_all_job_requisitions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY service_role_all_job_requisitions ON public.job_requisitions TO service_role USING (true) WITH CHECK (true);


--
-- Name: job_status_history service_role_all_job_status_history; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY service_role_all_job_status_history ON public.job_status_history TO service_role USING (true) WITH CHECK (true);


--
-- Name: manual_corrections; Type: ROW SECURITY; Schema: public; Owner: -
-- (Added during schema verification: the original dump left RLS off and no
--  policies on this table, unlike the other four. This brings it in line —
--  anon has no access; writes go through the service_role key only.)
--

ALTER TABLE public.manual_corrections ENABLE ROW LEVEL SECURITY;

--
-- Name: manual_corrections service_role_all_manual_corrections; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY service_role_all_manual_corrections ON public.manual_corrections TO service_role USING (true) WITH CHECK (true);


--
-- PostgreSQL database dump complete
--

\unrestrict JpW9bcjAeYrPE3echeE31JQgteFrFFP1CkkWod05TVUqtbSWw4hzvSApnHs3iNu

