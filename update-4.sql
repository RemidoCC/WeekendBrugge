-- =====================================================================
-- Vriendenweekend Brugge: update 4
-- - Vaste posten kunnen gekoppeld worden aan de boodschappenlijst
--   (het bedrag volgt dan automatisch het totaal van de lijst).
-- - Kosten per persoon: deelnemers en voorgeschoten uitgaven.
-- Alleen toevoegingen; bestaande gegevens blijven staan.
-- Eén keer draaien in de SQL Editor, na update-3.sql.
-- =====================================================================

-- 1. Koppeling vaste post -> boodschappenlijst
alter table weekend.items add column if not exists koppeling text;
alter table weekend.items drop constraint if exists items_koppeling_check;
alter table weekend.items add constraint items_koppeling_check check (koppeling is null or koppeling in ('ontbijt','drank'));

update weekend.items set koppeling = 'ontbijt' where dagdeel = 'vast' and titel like 'Ontbijt 2×%' and koppeling is null;
update weekend.items set koppeling = 'drank'   where dagdeel = 'vast' and titel like 'Drank & snacks%' and koppeling is null;

-- 2. Deelnemers en uitgaven
create table if not exists weekend.deelnemers (
  id uuid primary key default gen_random_uuid(),
  naam text not null check (length(naam) between 1 and 40),
  volgorde int not null default 0
);
create table if not exists weekend.uitgaven (
  id uuid primary key default gen_random_uuid(),
  omschrijving text not null check (length(omschrijving) between 1 and 120),
  bedrag numeric(10,2) not null check (bedrag > 0 and bedrag < 100000),
  betaald_door uuid not null references weekend.deelnemers(id) on delete restrict,
  voor uuid[] not null default '{}',          -- leeg = iedereen
  toegevoegd_op timestamptz not null default now(),
  bijgewerkt_door text not null default '' check (length(bijgewerkt_door) <= 40)
);
alter table weekend.deelnemers enable row level security;
alter table weekend.uitgaven enable row level security;
revoke all on weekend.deelnemers, weekend.uitgaven from public, anon, authenticated;

insert into weekend.deelnemers (naam, volgorde)
select v.naam, v.n from (values ('Remi',1),('Bas',2),('Vriend 3',3),('Vriend 4',4),('Vriend 5',5),('Vriend 6',6),('Vriend 7',7)) v(naam, n)
where not exists (select 1 from weekend.deelnemers);

-- 3. Functies
create or replace function public.weekend_kosten(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  return jsonb_build_object(
    'deelnemers', coalesce((select jsonb_agg(to_jsonb(d) order by d.volgorde, d.naam) from weekend.deelnemers d), '[]'::jsonb),
    'uitgaven',   coalesce((select jsonb_agg(to_jsonb(u) order by u.toegevoegd_op desc) from weekend.uitgaven u), '[]'::jsonb));
end $$;

create or replace function public.weekend_deelnemer_opslaan(p_code text, p_item jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r weekend.deelnemers;
begin
  perform weekend.controleer(p_code);
  if p_item ? 'id' and nullif(p_item->>'id','') is not null then
    update weekend.deelnemers set naam = coalesce(nullif(trim(p_item->>'naam'),''), naam)
    where id = (p_item->>'id')::uuid returning * into r;
    if r.id is null then raise exception 'Deelnemer niet gevonden'; end if;
  else
    insert into weekend.deelnemers (naam, volgorde)
    values (trim(p_item->>'naam'), coalesce((select max(volgorde)+1 from weekend.deelnemers), 1))
    returning * into r;
  end if;
  return to_jsonb(r);
end $$;

create or replace function public.weekend_deelnemer_verwijder(p_code text, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  if exists (select 1 from weekend.uitgaven where betaald_door = p_id or p_id = any(voor)) then
    raise exception 'Deze persoon staat nog bij een uitgave. Pas die eerst aan.';
  end if;
  delete from weekend.deelnemers where id = p_id;
end $$;

create or replace function public.weekend_uitgave_opslaan(p_code text, p_item jsonb, p_door text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r weekend.uitgaven; v_voor uuid[];
begin
  perform weekend.controleer(p_code);
  v_voor := case when p_item ? 'voor' then coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(p_item->'voor') x), '{}') else null end;
  if p_item ? 'id' and nullif(p_item->>'id','') is not null then
    update weekend.uitgaven set
      omschrijving = coalesce(p_item->>'omschrijving', omschrijving),
      bedrag = coalesce((p_item->>'bedrag')::numeric, bedrag),
      betaald_door = coalesce((p_item->>'betaald_door')::uuid, betaald_door),
      voor = coalesce(v_voor, voor),
      bijgewerkt_door = left(coalesce(p_door,''), 40)
    where id = (p_item->>'id')::uuid returning * into r;
    if r.id is null then raise exception 'Uitgave niet gevonden'; end if;
  else
    insert into weekend.uitgaven (omschrijving, bedrag, betaald_door, voor, bijgewerkt_door)
    values (p_item->>'omschrijving', (p_item->>'bedrag')::numeric, (p_item->>'betaald_door')::uuid, coalesce(v_voor, '{}'), left(coalesce(p_door,''), 40))
    returning * into r;
  end if;
  return to_jsonb(r);
end $$;

create or replace function public.weekend_uitgave_verwijder(p_code text, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  delete from weekend.uitgaven where id = p_id;
end $$;

revoke all on function public.weekend_kosten(text) from public;
revoke all on function public.weekend_deelnemer_opslaan(text, jsonb) from public;
revoke all on function public.weekend_deelnemer_verwijder(text, uuid) from public;
revoke all on function public.weekend_uitgave_opslaan(text, jsonb, text) from public;
revoke all on function public.weekend_uitgave_verwijder(text, uuid) from public;
grant execute on function public.weekend_kosten(text) to anon, authenticated;
grant execute on function public.weekend_deelnemer_opslaan(text, jsonb) to anon, authenticated;
grant execute on function public.weekend_deelnemer_verwijder(text, uuid) to anon, authenticated;
grant execute on function public.weekend_uitgave_opslaan(text, jsonb, text) to anon, authenticated;
grant execute on function public.weekend_uitgave_verwijder(text, uuid) to anon, authenticated;
comment on function public.weekend_kosten(text) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';
comment on function public.weekend_deelnemer_opslaan(text, jsonb) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';
comment on function public.weekend_deelnemer_verwijder(text, uuid) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';
comment on function public.weekend_uitgave_opslaan(text, jsonb, text) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';
comment on function public.weekend_uitgave_verwijder(text, uuid) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';

notify pgrst, 'reload schema';
