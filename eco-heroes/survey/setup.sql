-- Eco-Heroes: แบบประเมินความพึงพอใจ (ม.4) — วางใน Supabase > SQL Editor > Run (โปรเจกต์ verify Evaluation)
create table if not exists public.eh_satisfaction (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  gender text not null check (gender in ('m','f','x')),
  room text not null check (room ~ '^[0-9]{1,2}$'),
  scores smallint[] not null check (array_length(scores,1) = 20 and 1 <= all(scores) and 5 >= all(scores)),
  suggestion text check (suggestion is null or char_length(suggestion) <= 1000)
);
alter table public.eh_satisfaction enable row level security;
drop policy if exists "eh_sat_insert_anon" on public.eh_satisfaction;
drop policy if exists "eh_sat_select_anon" on public.eh_satisfaction;
create policy "eh_sat_insert_anon" on public.eh_satisfaction for insert to anon, authenticated with check (true);
create policy "eh_sat_select_anon" on public.eh_satisfaction for select to anon, authenticated using (true);
grant insert, select on public.eh_satisfaction to anon, authenticated;
