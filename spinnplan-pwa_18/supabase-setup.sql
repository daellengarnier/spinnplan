-- ============================================
-- SPINNPLAN – Supabase Schema
-- Paste this in Supabase > SQL Editor > Run
-- ============================================

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ── PROFILES (extends Supabase auth.users) ──
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  name text not null,
  is_admin boolean default false,
  notif_new_event boolean default false,
  notif_reminder boolean default false,
  created_at timestamptz default now()
);
alter table public.profiles enable row level security;
create policy "Users can read all profiles" on public.profiles for select using (true);
create policy "Users can update own profile" on public.profiles for update using (auth.uid() = id);
create policy "Users can insert own profile" on public.profiles for insert with check (auth.uid() = id);

-- ── EVENTS ──
create table public.events (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  date date not null,
  start_time text not null default '21:00',
  end_time text,
  dur_hours numeric not null default 1.5,
  num_blocks int not null default 2,
  enabled_roles jsonb not null default '{}',
  role_counts jsonb not null default '{}',
  fixed_roles jsonb not null default '{}',
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);
alter table public.events enable row level security;
create policy "Anyone logged in can read events" on public.events for select using (auth.role() = 'authenticated');
create policy "Only admins can insert events" on public.events for insert with check (
  exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
);
create policy "Only admins can update events" on public.events for update using (
  exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
);
create policy "Only admins can delete events" on public.events for delete using (
  exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
);

-- ── SLOTS ──
create table public.slots (
  id uuid default uuid_generate_v4() primary key,
  event_id uuid references public.events(id) on delete cascade not null,
  slot_key text not null,       -- e.g. "Bar_0"
  slot_index int not null,      -- 0 or 1 (which row)
  user_name text,               -- name of person signed up
  user_id uuid references public.profiles(id) on delete set null,
  updated_at timestamptz default now(),
  unique(event_id, slot_key, slot_index)
);
alter table public.slots enable row level security;
create policy "Anyone logged in can read slots" on public.slots for select using (auth.role() = 'authenticated');
create policy "Anyone logged in can upsert slots" on public.slots for insert with check (auth.role() = 'authenticated');
create policy "Users can update their own slot or admins can update any" on public.slots for update using (
  auth.uid() = user_id or
  exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
);
create policy "Users can delete their own slot or admins can delete any" on public.slots for delete using (
  auth.uid() = user_id or
  exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
);

-- ── TRIGGER: auto-create profile on signup ──
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, name, is_admin)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    false
  );
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ── Enable Realtime ──
alter publication supabase_realtime add table public.events;
alter publication supabase_realtime add table public.slots;

-- ── MAKE FIRST ADMIN ──
-- After registering your account, run this with your email:
-- update public.profiles set is_admin = true
-- where id = (select id from auth.users where email = 'admin@spinnerei.ch');
