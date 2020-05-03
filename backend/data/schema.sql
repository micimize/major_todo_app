--
-- PostgreSQL database dump
--

-- Dumped from database version 10.8
-- Dumped by pg_dump version 12.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: app_hidden; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app_hidden;


--
-- Name: app_private; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app_private;


--
-- Name: app_public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app_public;


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: finite_datetime; Type: DOMAIN; Schema: app_public; Owner: -
--

CREATE DOMAIN app_public.finite_datetime AS timestamp with time zone
	CONSTRAINT finite_datetime_check CHECK (isfinite(VALUE));


--
-- Name: DOMAIN finite_datetime; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON DOMAIN app_public.finite_datetime IS 'A timezone-enabled timestamp that is guaranteed to be finite';


--
-- Name: datetime_interval; Type: TYPE; Schema: app_public; Owner: -
--

CREATE TYPE app_public.datetime_interval AS (
	start app_public.finite_datetime,
	"end" app_public.finite_datetime
);


--
-- Name: firebase_uid; Type: DOMAIN; Schema: app_public; Owner: -
--

CREATE DOMAIN app_public.firebase_uid AS character varying;


--
-- Name: task_lifecycle; Type: TYPE; Schema: app_public; Owner: -
--

CREATE TYPE app_public.task_lifecycle AS ENUM (
    'TODO',
    'COMPLETED',
    'CANCELLED'
);


--
-- Name: tg__add_job(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg__add_job() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  perform graphile_worker.add_job(
    tg_argv[0],
    json_build_object('id', NEW.id),
    coalesce(tg_argv[1], public.gen_random_uuid()::text)
  );
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg__add_job(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg__add_job() IS 'Useful shortcut to create a job on insert/update. Pass the task name as the first trigger argument, and optionally the queue name as the second argument. The record id will automatically be available on the JSON payload.';


--
-- Name: tg__timestamps(); Type: FUNCTION; Schema: app_private; Owner: -
--

CREATE FUNCTION app_private.tg__timestamps() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  NEW.created = (case when TG_OP = 'INSERT' then NOW() else OLD.created end);
  NEW.updated = (case when TG_OP = 'UPDATE' and OLD.updated >= NOW() then OLD.updated + interval '1 millisecond' else NOW() end);
  return NEW;
end;
$$;


--
-- Name: FUNCTION tg__timestamps(); Type: COMMENT; Schema: app_private; Owner: -
--

COMMENT ON FUNCTION app_private.tg__timestamps() IS 'This trigger should be called on all tables with created, updated - it ensures that they cannot be manipulated and that updated will always be larger than the previous updated.';


SET default_tablespace = '';

--
-- Name: app_user; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.app_user (
    id app_public.firebase_uid NOT NULL,
    created app_public.finite_datetime DEFAULT now() NOT NULL,
    updated app_public.finite_datetime DEFAULT now() NOT NULL
);


--
-- Name: TABLE app_user; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON TABLE app_public.app_user IS 'A user who can log in to the application.';


--
-- Name: COLUMN app_user.id; Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON COLUMN app_public.app_user.id IS 'Unique identifier for the user.';


--
-- Name: current_app_user(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_app_user() RETURNS app_public.app_user
    LANGUAGE plpgsql
    AS $$
DECLARE
  sign_in_id app_public.firebase_uid;
  full_user app_public.app_user;
BEGIN
    sign_in_id := nullif(
      pg_catalog.current_setting('firebase.user.uid', true),
      ''
    )::app_public.firebase_uid;


    IF sign_in_id IS NULL THEN
      return null;
      --RAISE EXCEPTION 'Authentication not provided';
    END IF;

    SELECT * INTO full_user
    FROM app_public.app_user
    WHERE id = sign_in_id
    LIMIT 1;

    IF full_user.id IS NULL THEN
      INSERT INTO app_public.app_user (
        id
      ) VALUES (
        sign_in_id
      ) RETURNING * INTO full_user;
    END IF;

    RETURN full_user;
END;
$$;


--
-- Name: FUNCTION current_app_user(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.current_app_user() IS 'The currently logged in user (or null if not logged in).';


--
-- Name: current_user_id(); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_user_id() RETURNS app_public.firebase_uid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
  select id from app_public.current_app_user()
$$;


--
-- Name: FUNCTION current_user_id(); Type: COMMENT; Schema: app_public; Owner: -
--

COMMENT ON FUNCTION app_public.current_user_id() IS 'Handy method to get the current user ID, etc; in GraphQL, use `currentUser{id}` instead.';


--
-- Name: task; Type: TABLE; Schema: app_public; Owner: -
--

CREATE TABLE app_public.task (
    user_id app_public.firebase_uid DEFAULT app_public.current_user_id(),
    created app_public.finite_datetime DEFAULT now() NOT NULL,
    updated app_public.finite_datetime DEFAULT now() NOT NULL,
    id uuid DEFAULT public.uuid_generate_v1mc() NOT NULL,
    lifecycle app_public.task_lifecycle DEFAULT 'TODO'::app_public.task_lifecycle,
    closed app_public.finite_datetime,
    title text,
    description text,
    stopwatch_value app_public.datetime_interval[],
    CONSTRAINT task_title_check CHECK ((char_length(title) < 280))
);


--
-- Name: current_tasks(interval); Type: FUNCTION; Schema: app_public; Owner: -
--

CREATE FUNCTION app_public.current_tasks(closed_buffer interval DEFAULT '24:00:00'::interval) RETURNS SETOF app_public.task
    LANGUAGE sql STABLE
    AS $_$
    SELECT * FROM app_public.task
    WHERE
      COALESCE(closed, now()) > (
        now() - $1
      )
    ORDER BY
      created
    DESC
$_$;


--
-- Name: app_user app_user_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.app_user
    ADD CONSTRAINT app_user_pkey PRIMARY KEY (id);


--
-- Name: task task_pkey; Type: CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.task
    ADD CONSTRAINT task_pkey PRIMARY KEY (id);


--
-- Name: task_created_index; Type: INDEX; Schema: app_public; Owner: -
--

CREATE INDEX task_created_index ON app_public.task USING btree (created);


--
-- Name: app_user _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.app_user FOR EACH ROW EXECUTE PROCEDURE app_private.tg__timestamps();


--
-- Name: task _100_timestamps; Type: TRIGGER; Schema: app_public; Owner: -
--

CREATE TRIGGER _100_timestamps BEFORE INSERT OR UPDATE ON app_public.task FOR EACH ROW EXECUTE PROCEDURE app_private.tg__timestamps();


--
-- Name: task task_user_id_fkey; Type: FK CONSTRAINT; Schema: app_public; Owner: -
--

ALTER TABLE ONLY app_public.task
    ADD CONSTRAINT task_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_public.app_user(id) ON DELETE SET NULL;


--
-- Name: app_user; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.app_user ENABLE ROW LEVEL SECURITY;

--
-- Name: task manage_own; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY manage_own ON app_public.task USING (((user_id)::text = (app_public.current_user_id())::text));


--
-- Name: app_user select_all; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY select_all ON app_public.app_user FOR SELECT USING (true);


--
-- Name: task; Type: ROW SECURITY; Schema: app_public; Owner: -
--

ALTER TABLE app_public.task ENABLE ROW LEVEL SECURITY;

--
-- Name: app_user update_self; Type: POLICY; Schema: app_public; Owner: -
--

CREATE POLICY update_self ON app_public.app_user FOR UPDATE USING (((id)::text = (app_public.current_user_id())::text));


--
-- Name: SCHEMA app_hidden; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA app_hidden TO todo_app_visitor;


--
-- Name: SCHEMA app_public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA app_public TO todo_app_visitor;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO mjr;
GRANT ALL ON SCHEMA public TO todo_app;
GRANT USAGE ON SCHEMA public TO todo_app_visitor;


--
-- Name: FUNCTION tg__add_job(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg__add_job() FROM PUBLIC;


--
-- Name: FUNCTION tg__timestamps(); Type: ACL; Schema: app_private; Owner: -
--

REVOKE ALL ON FUNCTION app_private.tg__timestamps() FROM PUBLIC;


--
-- Name: TABLE app_user; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT ON TABLE app_public.app_user TO todo_app_visitor;


--
-- Name: FUNCTION current_app_user(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_app_user() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_app_user() TO todo_app_visitor;


--
-- Name: FUNCTION current_user_id(); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_user_id() FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_user_id() TO todo_app_visitor;


--
-- Name: TABLE task; Type: ACL; Schema: app_public; Owner: -
--

GRANT SELECT,DELETE ON TABLE app_public.task TO todo_app_visitor;


--
-- Name: COLUMN task.lifecycle; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(lifecycle),UPDATE(lifecycle) ON TABLE app_public.task TO todo_app_visitor;


--
-- Name: COLUMN task.closed; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(closed),UPDATE(closed) ON TABLE app_public.task TO todo_app_visitor;


--
-- Name: COLUMN task.title; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(title),UPDATE(title) ON TABLE app_public.task TO todo_app_visitor;


--
-- Name: COLUMN task.description; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(description),UPDATE(description) ON TABLE app_public.task TO todo_app_visitor;


--
-- Name: COLUMN task.stopwatch_value; Type: ACL; Schema: app_public; Owner: -
--

GRANT INSERT(stopwatch_value),UPDATE(stopwatch_value) ON TABLE app_public.task TO todo_app_visitor;


--
-- Name: FUNCTION current_tasks(closed_buffer interval); Type: ACL; Schema: app_public; Owner: -
--

REVOKE ALL ON FUNCTION app_public.current_tasks(closed_buffer interval) FROM PUBLIC;
GRANT ALL ON FUNCTION app_public.current_tasks(closed_buffer interval) TO todo_app_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: app_hidden; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA app_hidden REVOKE ALL ON SEQUENCES  FROM todo_app;
ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA app_hidden GRANT SELECT,USAGE ON SEQUENCES  TO todo_app_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: app_hidden; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA app_hidden REVOKE ALL ON FUNCTIONS  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA app_hidden REVOKE ALL ON FUNCTIONS  FROM todo_app;
ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA app_hidden GRANT ALL ON FUNCTIONS  TO todo_app_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: app_public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA app_public REVOKE ALL ON SEQUENCES  FROM todo_app;
ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA app_public GRANT SELECT,USAGE ON SEQUENCES  TO todo_app_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: app_public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA app_public REVOKE ALL ON FUNCTIONS  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA app_public REVOKE ALL ON FUNCTIONS  FROM todo_app;
ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA app_public GRANT ALL ON FUNCTIONS  TO todo_app_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA public REVOKE ALL ON SEQUENCES  FROM todo_app;
ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA public GRANT SELECT,USAGE ON SEQUENCES  TO todo_app_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA public REVOKE ALL ON FUNCTIONS  FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA public REVOKE ALL ON FUNCTIONS  FROM todo_app;
ALTER DEFAULT PRIVILEGES FOR ROLE todo_app IN SCHEMA public GRANT ALL ON FUNCTIONS  TO todo_app_visitor;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: -; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE todo_app REVOKE ALL ON FUNCTIONS  FROM PUBLIC;


--
-- PostgreSQL database dump complete
--

