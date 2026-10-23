-- Eco Hero Sentence Race · ตั้งค่าฐานข้อมูล (วางทั้งหมดใน Supabase > SQL Editor แล้วกด Run ครั้งเดียว)
create table if not exists public.ehsr_rooms (
  code text primary key,
  state jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.ehsr_room_keys (
  code text primary key references public.ehsr_rooms(code) on delete cascade,
  token text not null
);
create table if not exists public.ehsr_groups (
  room text not null references public.ehsr_rooms(code) on delete cascade,
  gid text not null check (gid ~ '^g[1-8]$'),
  name text not null check (char_length(name) <= 40),
  joined_at timestamptz not null default now(),
  primary key (room, gid)
);
create table if not exists public.ehsr_subs (
  id uuid primary key default gen_random_uuid(),
  room text not null references public.ehsr_rooms(code) on delete cascade,
  round_key text not null check (char_length(round_key) <= 40),
  gid text not null check (gid ~ '^g[1-8]$'),
  name text not null check (char_length(name) <= 40),
  faces jsonb not null check (jsonb_typeof(faces) = 'array' and jsonb_array_length(faces) <= 6),
  client_ms integer,
  created_at timestamptz not null default now(),
  unique (room, round_key, gid)
);
create index if not exists ehsr_subs_room_idx on public.ehsr_subs(room);

alter table public.ehsr_rooms enable row level security;
alter table public.ehsr_room_keys enable row level security;
alter table public.ehsr_groups enable row level security;
alter table public.ehsr_subs enable row level security;

create policy ehsr_rooms_read on public.ehsr_rooms for select to anon, authenticated using (true);
create policy ehsr_groups_read on public.ehsr_groups for select to anon, authenticated using (true);
create policy ehsr_subs_read on public.ehsr_subs for select to anon, authenticated using (true);
create policy ehsr_groups_insert on public.ehsr_groups for insert to anon, authenticated
  with check (exists (select 1 from public.ehsr_rooms r where r.code = room));
create policy ehsr_subs_insert on public.ehsr_subs for insert to anon, authenticated
  with check (exists (select 1 from public.ehsr_rooms r
                      where r.code = room and r.state->>'status' = 'play' and r.state->>'key' = round_key));

create or replace function public.ehsr_create_room(p_token text)
returns text language plpgsql security definer set search_path = public as $$
declare v_code text; begin
  if p_token is null or char_length(p_token) < 16 then raise exception 'bad token'; end if;
  delete from public.ehsr_rooms where updated_at < now() - interval '3 days';
  loop
    v_code := lpad((floor(random()*10000))::int::text, 4, '0');
    exit when not exists (select 1 from public.ehsr_rooms where code = v_code);
  end loop;
  insert into public.ehsr_rooms(code, state) values (v_code, '{"status":"idle","round":0,"total":3}'::jsonb);
  insert into public.ehsr_room_keys(code, token) values (v_code, p_token);
  return v_code;
end $$;

create or replace function public.ehsr_set_state(p_code text, p_token text, p_state jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_old jsonb; v_new jsonb; begin
  if not exists (select 1 from public.ehsr_room_keys where code = p_code and token = p_token) then
    raise exception 'not allowed';
  end if;
  select state into v_old from public.ehsr_rooms where code = p_code;
  v_new := p_state;
  if v_new->>'status' = 'play' and coalesce(v_old->>'key','') <> coalesce(v_new->>'key','') then
    v_new := v_new || jsonb_build_object('serverStart', floor(extract(epoch from now())*1000));
  elsif v_old ? 'serverStart' and v_old->>'key' = v_new->>'key' then
    v_new := v_new || jsonb_build_object('serverStart', v_old->'serverStart');
  end if;
  update public.ehsr_rooms set state = v_new, updated_at = now() where code = p_code;
  return v_new;
end $$;

create or replace function public.ehsr_reset(p_code text, p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.ehsr_room_keys where code = p_code and token = p_token) then
    raise exception 'not allowed';
  end if;
  delete from public.ehsr_subs where room = p_code;
  delete from public.ehsr_groups where room = p_code;
end $$;

create or replace function public.ehsr_check_token(p_code text, p_token text)
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.ehsr_room_keys where code = p_code and token = p_token);
$$;

revoke all on function public.ehsr_create_room(text) from public;
revoke all on function public.ehsr_set_state(text, text, jsonb) from public;
revoke all on function public.ehsr_reset(text, text) from public;
revoke all on function public.ehsr_check_token(text, text) from public;
grant execute on function public.ehsr_create_room(text) to anon, authenticated;
grant execute on function public.ehsr_set_state(text, text, jsonb) to anon, authenticated;
grant execute on function public.ehsr_reset(text, text) to anon, authenticated;
grant execute on function public.ehsr_check_token(text, text) to anon, authenticated;

alter publication supabase_realtime add table public.ehsr_rooms, public.ehsr_groups, public.ehsr_subs;
