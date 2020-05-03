--! Previous: sha1:4c2f06ca2b815247c552eb7ea91772074a3b35f6
--! Hash: sha1:14b843799d5825186246e11b81b96847128b060e

--! split: 1-auth.sql
/*
    HELPERS AND AUTHENTICATION
    * craetes tg__add_job and finite_datetime, and tg__timestamps helpers
    * creates app_user table, current_app_user, and current_user_id function
*/

drop trigger if exists _100_timestamps on app_public.task;
drop function if exists current_tasks;
drop table if exists task;
drop type if exists task_lifecycle;
drop type if exists datetime_interval;


drop function if exists app_public.current_app_user;
drop table if exists app_public.app_user;
drop function if exists app_public.current_user_id;
drop function if exists app_private.tg__add_job;
drop function if exists app_private.tg__timestamps;

drop domain if exists app_public.finite_datetime;
drop domain if exists app_public.firebase_uid; 

create domain app_public.firebase_uid as varchar ;

create function app_private.tg__add_job() returns trigger as $$
begin
  perform graphile_worker.add_job(
    tg_argv[0],
    json_build_object('id', NEW.id),
    coalesce(tg_argv[1], public.gen_random_uuid()::text)
  );
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

create table app_public.app_user (
  id app_public.firebase_uid primary key,
  created app_public.finite_datetime not null default now(),
  updated app_public.finite_datetime not null default now()
);
alter table app_public.app_user enable row level security;

comment on table app_public.app_user is
  E'A user who can log in to the application.';

comment on column app_public.app_user.id is
  E'Unique identifier for the user.';

create trigger _100_timestamps
  before insert or update on app_public.app_user
  for each row
  execute procedure app_private.tg__timestamps();

/**********/

CREATE FUNCTION app_public.current_app_user()
  RETURNS app_public.app_user AS $$
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
$$ LANGUAGE plpgsql;

comment on function app_public.current_app_user() is
  E'The currently logged in user (or null if not logged in).';

/**********/

create function app_public.current_user_id() returns app_public.firebase_uid as $$
  select id from app_public.current_app_user()
$$ language sql stable security definer set search_path to pg_catalog, public, pg_temp;

comment on function app_public.current_user_id() is
  E'Handy method to get the current user ID, etc; in GraphQL, use `currentUser{id}` instead.';
-- We've put this in public, but omitted it, because it's often useful for debugging auth issues.

/**********/

create policy select_all on app_public.app_user for select using (true);
create policy update_self on app_public.app_user for update using (id = app_public.current_user_id());
grant select on app_public.app_user to :DATABASE_VISITOR;
-- NOTE: `insert` is not granted, because we'll handle that separately
-- grant update(username, name, avatar_url) on app_public.app_user to :DATABASE_VISITOR;
-- NOTE: `delete` is not granted, because we require confirmation via request_account_deletion/confirm_account_deletion

--! split: 2-tasks.sql
/*
  TASKS
    * Instantiates app_public, app_private, and app_hidden 
    * sets permissions
    * creates a few helper functions
    * creates app_user table and current_user_id auth function
*/

drop trigger if exists _100_timestamps on app_public.task;
drop function if exists current_tasks;
drop table if exists task;
drop type if exists task_lifecycle;
drop type if exists datetime_interval;

create type task_lifecycle as enum (
  'TODO',
  'COMPLETED',
  'CANCELLED'
);

create type datetime_interval as (
  "start" finite_datetime,
  "end" finite_datetime
);

/*
CREATE DOMAIN stopwatch_interval AS datetime_interval[];
CHECK (
  SELECT * FROM UNNEST(VALUE)
  WHERE "end" is null
);
*/

create table app_public.task (
  user_id            app_public.firebase_uid default app_public.current_user_id()
                        references app_public.app_user(id)
                        on delete set null,
  created            finite_datetime not null default now(),
  updated            finite_datetime not null default now(),

  id                 uuid primary key default uuid_generate_v1mc(),

  lifecycle          task_lifecycle default 'TODO',
  closed             finite_datetime,

  title              text check (char_length(title) < 280),
  description        text,
  stopwatch_value    datetime_interval[]
);
alter table app_public.task enable row level security;

create index task_created_index ON app_public.task (created);


grant
  select,
  insert (lifecycle, closed, title, description, stopwatch_value),
  update (lifecycle, closed, title, description, stopwatch_value),
  delete
on app_public.task to :DATABASE_VISITOR;

create policy manage_own on app_public.task for all using (
  user_id = app_public.current_user_id()
);


create trigger _100_timestamps before insert or update on app_public.task
  for each row execute procedure app_private.tg__timestamps();

/*
CREATE DOMAIN timezone AS TEXT NOT NULL CHECK (
  now() AT TIME ZONE VALUE IS NOT NULL
);
 -- finite_datetime user_start_of_day)
*/

-- TODO should we surface a simple last "24 hours"
-- OR surface everything > user's "start of day"
CREATE OR REPLACE FUNCTION app_public.current_tasks(
  closed_buffer INTERVAL DEFAULT '24 hours'
)
  RETURNS SETOF app_public.task AS $$
    SELECT * FROM app_public.task
    WHERE
      COALESCE(closed, now()) > (
        now() - $1
      )
    ORDER BY
      created
    DESC
$$ LANGUAGE SQL STABLE;

-- create policy select_all on app_public.posts for select using (true);
-- create policy manage_own on app_public.posts for all using (author_id = app_public.current_user_id());
-- create policy manage_as_admin on app_public.posts for all using (exists (select 1 from app_public.users where is_admin is true and id = app_public.current_user_id()));
-- create table app_public.user_feed_posts (
--   id               serial primary key,
--   user_id          int not null references app_public.users on delete cascade,
--   post_id          int not null references app_public.posts on delete cascade,
--   created_at       timestamptz not null default now()
-- );
-- alter table app_public.user_feed_posts enable row level security;

-- grant select on app_public.user_feed_posts to :DATABASE_VISITOR;

-- create policy select_own on app_public.user_feed_posts for select using (user_id = app_public.current_user_id());

-- comment on table app_public.user_feed_posts is 'A feed of `Post`s relevant to a particular `User`.';
-- comment on column app_public.user_feed_posts.id is 'An identifier for this entry in the feed.';
-- comment on column app_public.user_feed_posts.created_at is 'The time this feed item was added.';
