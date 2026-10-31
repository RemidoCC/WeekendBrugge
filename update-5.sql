-- =====================================================================
-- Vriendenweekend Brugge: update 5
-- - Reserveringsstatus en adres per optie
-- - Takenlijst "Te doen" met deadlines
-- - Adres van het huisje
-- - Volgorde van lijstregels (slepen)
-- - Foto van het bonnetje bij een uitgave
-- Alleen toevoegingen; bestaande gegevens blijven staan.
-- Eén keer draaien in de SQL Editor, na update-4.sql.
-- =====================================================================

-- 1. Opties: reservering en adres
alter table weekend.items add column if not exists reservering text;
alter table weekend.items add column if not exists adres text not null default '';
alter table weekend.items drop constraint if exists items_reservering_check;
alter table weekend.items add constraint items_reservering_check check (reservering is null or reservering in ('te_reserveren','gereserveerd','betaald'));
alter table weekend.items drop constraint if exists items_adres_check;
alter table weekend.items add constraint items_adres_check check (length(adres) <= 200);

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
      adres = coalesce(p_item->>'adres', adres),
      prijs = coalesce((p_item->>'prijs')::numeric, prijs),
      prijs_type = coalesce(p_item->>'prijs_type', prijs_type),
      status = coalesce(p_item->>'status', status),
      reservering = case when p_item ? 'reservering' then nullif(p_item->>'reservering','') else reservering end,
      tijd_van = case when p_item ? 'tijd_van' then nullif(p_item->>'tijd_van','')::time else tijd_van end,
      tijd_tot = case when p_item ? 'tijd_tot' then nullif(p_item->>'tijd_tot','')::time else tijd_tot end,
      bijgewerkt_op = now(),
      bijgewerkt_door = left(coalesce(p_door,''), 40)
    where id = (p_item->>'id')::uuid
    returning * into r;
    if r.id is null then raise exception 'Optie niet gevonden'; end if;
  else
    insert into weekend.items (dagdeel, titel, omschrijving, link, adres, prijs, prijs_type, status, reservering, gekozen, volgorde, tijd_van, tijd_tot, bijgewerkt_door)
    values (
      p_item->>'dagdeel', p_item->>'titel', coalesce(p_item->>'omschrijving',''), coalesce(p_item->>'link',''), coalesce(p_item->>'adres',''),
      coalesce((p_item->>'prijs')::numeric, 0), coalesce(p_item->>'prijs_type','pp'), coalesce(p_item->>'status','geschat'),
      nullif(p_item->>'reservering',''),
      coalesce((p_item->>'dagdeel') = 'vast', false),
      coalesce((select max(volgorde)+1 from weekend.items where dagdeel = p_item->>'dagdeel'), 0),
      nullif(p_item->>'tijd_van','')::time, nullif(p_item->>'tijd_tot','')::time,
      left(coalesce(p_door,''), 40))
    returning * into r;
  end if;
  return to_jsonb(r);
end $$;

-- Adressen voor de bekende opties (alleen waar nog niets staat)
update weekend.items i set adres = a.adres
from (values
  ('Brouwerij De Halve Maan%', 'Brouwerij De Halve Maan, Walplein 26, 8000 Brugge'),
  ('Rondvaart op de reien%', 'Rozenhoedkaai, 8000 Brugge'),
  ('Vrij rondstruinen%', 'Markt, 8000 Brugge'),
  ('Bieratelier%', 'Bieratelier, Brugge'),
  ('Theeschenkerij bij kasteel Bulskampveld%', 'Kasteel Bulskampveld, 8730 Beernem'),
  ('Brouwerij Rodenbach%', 'Brouwerij Rodenbach, Roeselare'),
  ('Belfort van Brugge%', 'Belfort, Markt 7, 8000 Brugge'),
  ('Bulskampveld-wandelroute%', 'Parking Driekoningen, Wellingstraat, 8730 Beernem'),
  ('Damme – Damse Vaart%', 'Markt, 8340 Damme'),
  ('Jeneverstokerij Filliers%', 'Filliers Distillery, Deinze'),
  ('Brouwerij Bourgogne des Flandres%', 'Brouwerij Bourgogne des Flandres, Brugge'),
  ('Westhoek: Sint-Bernardus%', 'In de Vrede, Donkerstraat 13, 8640 Westvleteren'),
  ('Gran Kaffee De Passage%', 'Gran Kaffee De Passage, Dweersstraat 26, 8000 Brugge'),
  ('Bierbrasserie Cambrinus%', 'Bierbrasserie Cambrinus, Brugge'),
  ('''t Nieuw Walnutje%', '''t Nieuw Walnutje, Walplein, 8000 Brugge'),
  ('Mozarthuys%', 'Mozarthuys, Huidenvettersplein 1, 8000 Brugge'),
  ('🚆 OV-optie%', 'Station Beernem'),
  ('🚌 OV-optie%', 'Beernem Gemeentehuis'),
  ('Brunch bij Willa%', 'Willa Brunch & Coffee, Sint-Jansplein 9, 8000 Brugge'),
  ('Bowlen bij Bowl Inn%', 'Bowl Inn, Koning Leopold III-laan 68, 8200 Sint-Michiels')
) as a(patroon, adres)
where i.titel like a.patroon and i.adres = '';

-- 2. Instellingen (adres van het huisje)
create table if not exists weekend.instellingen (
  sleutel text primary key check (sleutel in ('adres_huisje')),
  waarde text not null default '' check (length(waarde) <= 200)
);
alter table weekend.instellingen enable row level security;
revoke all on weekend.instellingen from public, anon, authenticated;

create or replace function public.weekend_instellingen(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  return coalesce((select jsonb_object_agg(sleutel, waarde) from weekend.instellingen), '{}'::jsonb);
end $$;

create or replace function public.weekend_instelling_opslaan(p_code text, p_sleutel text, p_waarde text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  insert into weekend.instellingen (sleutel, waarde) values (p_sleutel, coalesce(p_waarde,''))
  on conflict (sleutel) do update set waarde = excluded.waarde;
end $$;

-- 3. Takenlijst
create table if not exists weekend.taken (
  id uuid primary key default gen_random_uuid(),
  titel text not null check (length(titel) between 1 and 160),
  deadline date,
  wie text not null default '' check (length(wie) <= 40),
  klaar boolean not null default false,
  toegevoegd_op timestamptz not null default now(),
  bijgewerkt_door text not null default '' check (length(bijgewerkt_door) <= 40)
);
alter table weekend.taken enable row level security;
revoke all on weekend.taken from public, anon, authenticated;

insert into weekend.taken (titel, deadline, bijgewerkt_door, toegevoegd_op)
select v.titel, v.deadline::date, 'Claude', now() + (v.n || ' seconds')::interval
from (values
  (1, 'Namen van de deelnemers invullen in de app', '2026-11-01'),
  (2, 'Kookwereld bestellen (besteltermijn checken)', '2026-11-06'),
  (3, 'Beslissen waar we zaterdagavond eten, zo nodig reserveren', '2026-11-07'),
  (4, 'Spel voor zaterdagavond kiezen en spullen regelen', '2026-11-08'),
  (5, 'Bij de verhuurder checken: koffieapparaat, beddengoed en handdoeken', '2026-11-09'),
  (6, 'Sleutel en aankomstinstructies huisje opvragen', '2026-11-10'),
  (7, 'LEZ-registratie als we via Gent of Antwerpen rijden', '2026-11-11'),
  (8, 'Boodschappen doen', '2026-11-12'),
  (9, 'Speciaalbier halen (Belgische supermarkt of De Halve Maan)', '2026-11-13')
) as v(n, titel, deadline)
where not exists (select 1 from weekend.taken);

create or replace function public.weekend_taken(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  return coalesce((select jsonb_agg(to_jsonb(t) order by t.klaar, t.deadline nulls last, t.toegevoegd_op) from weekend.taken t), '[]'::jsonb);
end $$;

create or replace function public.weekend_taak_opslaan(p_code text, p_item jsonb, p_door text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r weekend.taken;
begin
  perform weekend.controleer(p_code);
  if p_item ? 'id' and nullif(p_item->>'id','') is not null then
    update weekend.taken set
      titel = coalesce(p_item->>'titel', titel),
      deadline = case when p_item ? 'deadline' then nullif(p_item->>'deadline','')::date else deadline end,
      wie = coalesce(p_item->>'wie', wie),
      klaar = coalesce((p_item->>'klaar')::boolean, klaar),
      bijgewerkt_door = left(coalesce(p_door,''), 40)
    where id = (p_item->>'id')::uuid returning * into r;
    if r.id is null then raise exception 'Taak niet gevonden'; end if;
  else
    insert into weekend.taken (titel, deadline, wie, bijgewerkt_door)
    values (p_item->>'titel', nullif(p_item->>'deadline','')::date, coalesce(p_item->>'wie',''), left(coalesce(p_door,''), 40))
    returning * into r;
  end if;
  return to_jsonb(r);
end $$;

create or replace function public.weekend_taak_verwijder(p_code text, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  delete from weekend.taken where id = p_id;
end $$;

-- 4. Volgorde van lijstregels
alter table weekend.boodschappen add column if not exists volgorde int not null default 0;
update weekend.boodschappen b set volgorde = s.rn
from (select id, row_number() over (partition by lijst, categorie order by toegevoegd_op) as rn from weekend.boodschappen) s
where s.id = b.id and b.volgorde = 0;

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
    if r.id is null then raise exception 'Regel niet gevonden'; end if;
  else
    insert into weekend.boodschappen (lijst, naam, hoeveelheid, categorie, wie, prijs, volgorde, bijgewerkt_door)
    values (coalesce(nullif(p_item->>'lijst',''),'boodschappen'), p_item->>'naam', coalesce(p_item->>'hoeveelheid',''),
            coalesce(p_item->>'categorie','overig'), coalesce(p_item->>'wie',''),
            nullif(p_item->>'prijs','')::numeric,
            coalesce((select max(volgorde)+1 from weekend.boodschappen where lijst = coalesce(nullif(p_item->>'lijst',''),'boodschappen') and categorie = coalesce(p_item->>'categorie','overig')), 1),
            left(coalesce(p_door,''), 40))
    returning * into r;
  end if;
  return to_jsonb(r);
end $$;

create or replace function public.weekend_boodschap_volgorde(p_code text, p_ids jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  update weekend.boodschappen b set volgorde = x.n
  from (select value::uuid as id, ordinality::int as n from jsonb_array_elements_text(p_ids) with ordinality) x
  where b.id = x.id;
end $$;

-- 5. Bonnetjes bij uitgaven (verkleinde foto, apart opgehaald)
alter table weekend.uitgaven add column if not exists bon text;
alter table weekend.uitgaven drop constraint if exists uitgaven_bon_check;
alter table weekend.uitgaven add constraint uitgaven_bon_check check (bon is null or (bon like 'data:image/%' and length(bon) <= 1500000));

create or replace function public.weekend_kosten(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  return jsonb_build_object(
    'deelnemers', coalesce((select jsonb_agg(to_jsonb(d) order by d.volgorde, d.naam) from weekend.deelnemers d), '[]'::jsonb),
    'uitgaven',   coalesce((select jsonb_agg((to_jsonb(u) - 'bon') || jsonb_build_object('heeft_bon', u.bon is not null) order by u.toegevoegd_op desc) from weekend.uitgaven u), '[]'::jsonb));
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
      bon = case when p_item ? 'bon' then nullif(p_item->>'bon','') else bon end,
      bijgewerkt_door = left(coalesce(p_door,''), 40)
    where id = (p_item->>'id')::uuid returning * into r;
    if r.id is null then raise exception 'Uitgave niet gevonden'; end if;
  else
    insert into weekend.uitgaven (omschrijving, bedrag, betaald_door, voor, bon, bijgewerkt_door)
    values (p_item->>'omschrijving', (p_item->>'bedrag')::numeric, (p_item->>'betaald_door')::uuid, coalesce(v_voor, '{}'),
            nullif(p_item->>'bon',''), left(coalesce(p_door,''), 40))
    returning * into r;
  end if;
  return (to_jsonb(r) - 'bon') || jsonb_build_object('heeft_bon', r.bon is not null);
end $$;

create or replace function public.weekend_bon(p_code text, p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  return (select bon from weekend.uitgaven where id = p_id);
end $$;

-- 6. Rechten
do $$
declare f text;
begin
  foreach f in array array[
    'public.weekend_instellingen(text)', 'public.weekend_instelling_opslaan(text, text, text)',
    'public.weekend_taken(text)', 'public.weekend_taak_opslaan(text, jsonb, text)', 'public.weekend_taak_verwijder(text, uuid)',
    'public.weekend_boodschap_volgorde(text, jsonb)', 'public.weekend_bon(text, uuid)']
  loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
    execute format('comment on function %s is %L', f, 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.');
  end loop;
end $$;

notify pgrst, 'reload schema';
