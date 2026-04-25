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
  notif_48h_reminder boolean default false,
  notif_absence_alert boolean default false,
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
  role_blocks jsonb not null default '{}',
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
create policy "Users can update their own slot or empty slots or admins can update any" on public.slots for update using (
  auth.uid() = user_id or
  user_id is null or
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

-- ── NOTIFICATIONS ──
create table public.notifications (
  id uuid default uuid_generate_v4() primary key,
  type text not null,
  title text not null,
  body text,
  read_by uuid[] default '{}',
  created_at timestamptz default now()
);
alter table public.notifications enable row level security;
create policy "Anyone logged in can read notifications" on public.notifications for select using (auth.role() = 'authenticated');
create policy "Only admins can insert notifications" on public.notifications for insert with check (
  exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
);
create policy "Anyone logged in can update notifications" on public.notifications for update using (auth.role() = 'authenticated');

-- ── PUSH SUBSCRIPTIONS ──
create table public.push_subscriptions (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz default now()
);
alter table public.push_subscriptions enable row level security;
create policy "Users can manage their own subscriptions" on public.push_subscriptions for all using (auth.uid() = user_id);
create policy "Service role can read all subscriptions" on public.push_subscriptions for select using (true);

-- ── Enable Realtime ──
alter publication supabase_realtime add table public.events;
alter publication supabase_realtime add table public.slots;

-- ── MAKE FIRST ADMIN ──
-- After registering your account, run this with your email:
-- update public.profiles set is_admin = true
-- where id = (select id from auth.users where email = 'admin@spinnerei.ch');

-- ══════════════════════════════════════════════
-- MIGRATION: Run these on existing installations
-- ══════════════════════════════════════════════
-- ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS notif_48h_reminder boolean default false;
-- ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS notif_absence_alert boolean default false;
-- ALTER TABLE public.events ADD COLUMN IF NOT EXISTS role_blocks jsonb not null default '{}';
--
-- -- Fix slots RLS: allow authenticated users to claim empty slots
-- DROP POLICY IF EXISTS "Users can update their own slot or admins can update any" ON public.slots;
-- CREATE POLICY "Users can update their own slot or empty slots or admins can update any" ON public.slots FOR UPDATE USING (
--   auth.uid() = user_id OR
--   user_id IS NULL OR
--   EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
-- );
--
-- -- Push subscriptions table (for native Web Push)
-- CREATE TABLE IF NOT EXISTS public.push_subscriptions (
--   id uuid default uuid_generate_v4() primary key,
--   user_id uuid references public.profiles(id) on delete cascade,
--   endpoint text not null unique,
--   p256dh text not null,
--   auth text not null,
--   created_at timestamptz default now()
-- );
-- ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "Users can manage their own subscriptions" ON public.push_subscriptions FOR ALL USING (auth.uid() = user_id);
-- CREATE POLICY "Service role can read all subscriptions" ON public.push_subscriptions FOR SELECT USING (true);
