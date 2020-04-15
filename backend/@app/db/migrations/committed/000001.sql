--! Previous: -
--! Hash: sha1:76cc289e5a01b745e6ce3acbe13dc7a40657f350

drop schema if exists app_public cascade;

alter default privileges revoke all on sequences from public;
alter default privileges revoke all on functions from public;

-- By default the public schema is owned by `postgres`; we need superuser privileges to change this :(
-- alter schema public owner to :DATABASE_OWNER;

revoke all on schema public from public;
grant all on schema public to :DATABASE_OWNER;

create schema app_public;
grant usage on schema public, app_public to :DATABASE_VISITOR;

/**********/

drop schema if exists app_hidden cascade;
create schema app_hidden;
grant usage on schema app_hidden to :DATABASE_VISITOR;
alter default privileges in schema app_hidden grant usage, select on sequences to :DATABASE_VISITOR;

/**********/

alter default privileges in schema public, app_public, app_hidden grant usage, select on sequences to :DATABASE_VISITOR;
alter default privileges in schema public, app_public, app_hidden grant execute on functions to :DATABASE_VISITOR;

/**********/

drop schema if exists app_private cascade;
create schema app_private;

/**********/

create function app_private.tg__add_job() returns trigger as $$
begin
  perform graphile_worker.add_job(tg_argv[0], json_build_object('id', NEW.id), coalesce(tg_argv[1], public.gen_random_uuid()::text));
  return NEW;
end;
$$ language plpgsql volatile security definer set search_path to pg_catalog, public, pg_temp;
comment on function app_private.tg__add_job() is
  E'Useful shortcut to create a job on insert/update. Pass the task name as the first trigger argument, and optionally the queue name as the second argument. The record id will automatically be available on the JSON payload.';

/**********/

create domain app_public.finite_datetime as timestamptz check (
  isfinite(value)
);
comment on domain finite_datetime is E'A timezone-enabled timestamp that is guaranteed to be finite';

/**********/

create function app_private.tg__timestamps() returns trigger as $$
begin
  NEW.created = (case when TG_OP = 'INSERT' then NOW() else OLD.created end);
  NEW.updated = (case when TG_OP = 'UPDATE' and OLD.updated >= NOW() then OLD.updated + interval '1 millisecond' else NOW() end);
  return NEW;
end;
$$ language plpgsql volatile set search_path to pg_catalog, public, pg_temp;
comment on function app_private.tg__timestamps() is
  E'This trigger should be called on all tables with created, updated - it ensures that they cannot be manipulated and that updated will always be larger than the previous updated.';

/**********/

create function app_public.current_user_id() returns uuid as $$
  select nullif(pg_catalog.current_setting('firebase.user.uid', true), '')::uuid;
$$ language sql stable;
comment on function app_public.current_user_id() is
  E'Handy method to get the current user ID, etc; in GraphQL, use `currentUser{id}` instead.';
-- We've put this in public, but omitted it, because it's often useful for debugging auth issues.

/**********/

create table app_public.app_user (
  id uuid primary key,
  created app_public.finite_datetime not null default now(),
  updated app_public.finite_datetime not null default now()
);
alter table app_public.app_user enable row level security;

create policy select_all on app_public.app_user for select using (true);
create policy update_self on app_public.app_user for update using (id = app_public.current_user_id());
grant select on app_public.app_user to :DATABASE_VISITOR;
-- NOTE: `insert` is not granted, because we'll handle that separately
-- grant update(username, name, avatar_url) on app_public.app_user to :DATABASE_VISITOR;
-- NOTE: `delete` is not granted, because we require confirmation via request_account_deletion/confirm_account_deletion

comment on table app_public.app_user is
  E'A user who can log in to the application.';

comment on column app_public.app_user.id is
  E'Unique identifier for the user.';

create trigger _100_timestamps
  before insert or update on app_public.app_user
  for each row
  execute procedure app_private.tg__timestamps();


CREATE FUNCTION app_public.current_app_user()
  RETURNS app_public.app_user AS $$
DECLARE
  sign_in_id uuid;
  full_user app_public.app_user;
BEGIN
    sign_in_id := current_user_id();

    IF sign_in_id IS NULL THEN
      RAISE EXCEPTION 'Authentication not provided';
    END IF;

    SELECT * INTO full_user
    FROM app_public.app_user
    WHERE id = app_public.current_user_id()
    LIMIT 1;

    IF full_user.id IS NULL THEN
      INSERT INTO app_public.app_user (
        id
      ) VALUES (
        current_user_id()
      ) RETURNING * INTO full_user;
    END IF;

    RETURN full_user;
END;
$$ LANGUAGE plpgsql;

comment on function app_public.current_app_user() is
  E'The currently logged in user (or null if not logged in).';
