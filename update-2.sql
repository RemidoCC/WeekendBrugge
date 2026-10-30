-- =====================================================================
-- Vriendenweekend Brugge: update 2
-- Meerdere keuzes per dagdeel, tijden bij activiteiten, boodschappenlijst.
-- Alleen toevoegingen: bestaande opties en keuzes blijven staan.
-- Eén keer draaien in de SQL Editor van het Supabase-project.
-- =====================================================================

alter table weekend.items add column if not exists tijd_van time, add column if not exists tijd_tot time;

create table if not exists weekend.boodschappen (
  id uuid primary key default gen_random_uuid(),
  naam text not null check (length(naam) between 1 and 120),
  hoeveelheid text not null default '' check (length(hoeveelheid) <= 60),
  categorie text not null default 'overig' check (categorie in ('ontbijt','lunch','diner','drank','snacks','overig')),
  wie text not null default '' check (length(wie) <= 40),
  prijs numeric(10,2) check (prijs is null or (prijs >= 0 and prijs < 10000)),
  afgevinkt boolean not null default false,
  toegevoegd_op timestamptz not null default now(),
  bijgewerkt_door text not null default '' check (length(bijgewerkt_door) <= 40)
);
alter table weekend.boodschappen enable row level security;
revoke all on weekend.boodschappen from public, anon, authenticated;

create or replace function public.weekend_opslaan(p_code text, p_item jsonb, p_door text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r weekend.items;
begin
  perform weekend.controleer(p_code);
  if p_item ? 'id' and nullif(p_item->>'id','') is not null then
    update weekend.items set
      titel = coalesce(p_item->>'titel', titel),
      omschrijving = coalesce(p_item->>'omschrijving', omschrijving),
      link = coalesce(p_item->>'link', link),
      prijs = coalesce((p_item->>'prijs')::numeric, prijs),
      prijs_type = coalesce(p_item->>'prijs_type', prijs_type),
      status = coalesce(p_item->>'status', status),
      tijd_van = case when p_item ? 'tijd_van' then nullif(p_item->>'tijd_van','')::time else tijd_van end,
      tijd_tot = case when p_item ? 'tijd_tot' then nullif(p_item->>'tijd_tot','')::time else tijd_tot end,
      bijgewerkt_op = now(),
      bijgewerkt_door = left(coalesce(p_door,''), 40)
    where id = (p_item->>'id')::uuid
    returning * into r;
    if r.id is null then raise exception 'Optie niet gevonden'; end if;
  else
    insert into weekend.items (dagdeel, titel, omschrijving, link, prijs, prijs_type, status, gekozen, volgorde, tijd_van, tijd_tot, bijgewerkt_door)
    values (
      p_item->>'dagdeel', p_item->>'titel', coalesce(p_item->>'omschrijving',''), coalesce(p_item->>'link',''),
      coalesce((p_item->>'prijs')::numeric, 0), coalesce(p_item->>'prijs_type','pp'), coalesce(p_item->>'status','geschat'),
      coalesce((p_item->>'dagdeel') = 'vast', false),
      coalesce((select max(volgorde)+1 from weekend.items where dagdeel = p_item->>'dagdeel'), 0),
      nullif(p_item->>'tijd_van','')::time, nullif(p_item->>'tijd_tot','')::time,
      left(coalesce(p_door,''), 40))
    returning * into r;
  end if;
  return to_jsonb(r);
end $$;

-- Meerdere keuzes per dagdeel: kiezen zet alleen deze optie aan of uit.
create or replace function public.weekend_kies(p_code text, p_id uuid, p_door text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  update weekend.items set gekozen = not gekozen, bijgewerkt_op = now(), bijgewerkt_door = left(coalesce(p_door,''),40) where id = p_id;
  if not found then raise exception 'Optie niet gevonden'; end if;
end $$;

create or replace function public.weekend_boodschappen(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  return coalesce((select jsonb_agg(to_jsonb(b) order by b.afgevinkt, b.categorie, b.toegevoegd_op) from weekend.boodschappen b), '[]'::jsonb);
end $$;

create or replace function public.weekend_boodschap_opslaan(p_code text, p_item jsonb, p_door text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r weekend.boodschappen;
begin
  perform weekend.controleer(p_code);
  if p_item ? 'id' and nullif(p_item->>'id','') is not null then
    update weekend.boodschappen set
      naam = coalesce(p_item->>'naam', naam),
      hoeveelheid = coalesce(p_item->>'hoeveelheid', hoeveelheid),
      categorie = coalesce(p_item->>'categorie', categorie),
      wie = coalesce(p_item->>'wie', wie),
      prijs = case when p_item ? 'prijs' then nullif(p_item->>'prijs','')::numeric else prijs end,
      afgevinkt = coalesce((p_item->>'afgevinkt')::boolean, afgevinkt),
      bijgewerkt_door = left(coalesce(p_door,''), 40)
    where id = (p_item->>'id')::uuid
    returning * into r;
    if r.id is null then raise exception 'Boodschap niet gevonden'; end if;
  else
    insert into weekend.boodschappen (naam, hoeveelheid, categorie, wie, prijs, bijgewerkt_door)
    values (p_item->>'naam', coalesce(p_item->>'hoeveelheid',''), coalesce(p_item->>'categorie','overig'),
            coalesce(p_item->>'wie',''), nullif(p_item->>'prijs','')::numeric, left(coalesce(p_door,''), 40))
    returning * into r;
  end if;
  return to_jsonb(r);
end $$;

create or replace function public.weekend_boodschap_verwijder(p_code text, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  delete from weekend.boodschappen where id = p_id;
end $$;

revoke all on function public.weekend_boodschappen(text) from public;
revoke all on function public.weekend_boodschap_opslaan(text, jsonb, text) from public;
revoke all on function public.weekend_boodschap_verwijder(text, uuid) from public;
grant execute on function public.weekend_boodschappen(text) to anon, authenticated;
grant execute on function public.weekend_boodschap_opslaan(text, jsonb, text) to anon, authenticated;
grant execute on function public.weekend_boodschap_verwijder(text, uuid) to anon, authenticated;
comment on function public.weekend_boodschappen(text) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';
comment on function public.weekend_boodschap_opslaan(text, jsonb, text) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';
comment on function public.weekend_boodschap_verwijder(text, uuid) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';

-- Reistijden van de OV-opties naar Brugge (zaterdag 14 november)
update weekend.items set tijd_van = '13:11', tijd_tot = '19:41' where dagdeel = 'za-middag' and titel like '🚆 OV-optie A%' and tijd_van is null;
update weekend.items set tijd_van = '13:11', tijd_tot = '20:41' where dagdeel = 'za-middag' and titel like '🚆 OV-optie B%' and tijd_van is null;
update weekend.items set tijd_van = '12:45', tijd_tot = '20:00' where dagdeel = 'za-middag' and titel like '🚌 OV-optie C%' and tijd_van is null;

-- PostgREST de nieuwe functies direct laten zien
notify pgrst, 'reload schema';
