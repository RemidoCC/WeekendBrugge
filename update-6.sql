-- =====================================================================
-- Vriendenweekend Brugge: update 6
-- - Lichte versiecheck: de app haalt alleen alles op als er iets veranderd is
-- - Wie wijzigde wat en wanneer, ook voor lijsten, taken en uitgaven
-- - Wijzigingen die offline zijn gedaan veilig nasturen (eigen id's, expliciet kiezen)
-- Alleen toevoegingen; bestaande gegevens blijven staan.
-- Eén keer draaien in de SQL Editor, na update-5.sql.
-- =====================================================================

-- 1. Tijdstip van de laatste wijziging
alter table weekend.boodschappen add column if not exists bijgewerkt_op timestamptz;
alter table weekend.taken        add column if not exists bijgewerkt_op timestamptz;
alter table weekend.uitgaven     add column if not exists bijgewerkt_op timestamptz;
update weekend.boodschappen set bijgewerkt_op = toegevoegd_op where bijgewerkt_op is null;
update weekend.taken        set bijgewerkt_op = toegevoegd_op where bijgewerkt_op is null;
update weekend.uitgaven     set bijgewerkt_op = toegevoegd_op where bijgewerkt_op is null;
alter table weekend.boodschappen alter column bijgewerkt_op set default now(), alter column bijgewerkt_op set not null;
alter table weekend.taken        alter column bijgewerkt_op set default now(), alter column bijgewerkt_op set not null;
alter table weekend.uitgaven     alter column bijgewerkt_op set default now(), alter column bijgewerkt_op set not null;

-- Alleen echte wijzigingen tellen (verslepen telt niet)
create or replace function weekend.zet_bijgewerkt() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (to_jsonb(new) - 'volgorde' - 'bijgewerkt_op') is distinct from (to_jsonb(old) - 'volgorde' - 'bijgewerkt_op') then
    new.bijgewerkt_op := now();
  else
    new.bijgewerkt_op := old.bijgewerkt_op;
  end if;
  return new;
end $$;
drop trigger if exists bijgewerkt on weekend.boodschappen;
drop trigger if exists bijgewerkt on weekend.taken;
drop trigger if exists bijgewerkt on weekend.uitgaven;
create trigger bijgewerkt before update on weekend.boodschappen for each row execute function weekend.zet_bijgewerkt();
create trigger bijgewerkt before update on weekend.taken        for each row execute function weekend.zet_bijgewerkt();
create trigger bijgewerkt before update on weekend.uitgaven     for each row execute function weekend.zet_bijgewerkt();

-- 2. Versie van alle gegevens in één klein antwoord
create or replace function public.weekend_versie(p_code text) returns text
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  return md5(
    coalesce((select string_agg(md5(to_jsonb(i)::text), '' order by i.id) from weekend.items i), '') ||
    coalesce((select string_agg(md5(to_jsonb(b)::text), '' order by b.id) from weekend.boodschappen b), '') ||
    coalesce((select string_agg(md5(to_jsonb(t)::text), '' order by t.id) from weekend.taken t), '') ||
    coalesce((select string_agg(md5((to_jsonb(u) - 'bon')::text || (u.bon is not null)::text), '' order by u.id) from weekend.uitgaven u), '') ||
    coalesce((select string_agg(md5(to_jsonb(d)::text), '' order by d.id) from weekend.deelnemers d), '') ||
    coalesce((select string_agg(md5(to_jsonb(s)::text), '' order by s.sleutel) from weekend.instellingen s), ''));
end $$;

-- 3. Expliciet kiezen (veilig om opnieuw te versturen)
create or replace function public.weekend_kies_zet(p_code text, p_id uuid, p_gekozen boolean, p_door text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  update weekend.items set gekozen = p_gekozen, bijgewerkt_op = now(), bijgewerkt_door = left(coalesce(p_door,''), 40)
  where id = p_id and gekozen is distinct from p_gekozen;
end $$;

-- 4. Opslaan met een id dat de app zelf maakt (nieuw of bestaand)
create or replace function public.weekend_opslaan(p_code text, p_item jsonb, p_door text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r weekend.items; v_id uuid := nullif(p_item->>'id','')::uuid;
begin
  perform weekend.controleer(p_code);
  if v_id is not null then
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
    where id = v_id
    returning * into r;
    if r.id is not null then return to_jsonb(r); end if;
    if not (p_item ? 'titel' and p_item ? 'dagdeel') then raise exception 'Optie niet gevonden'; end if;
  end if;
  insert into weekend.items (id, dagdeel, titel, omschrijving, link, adres, prijs, prijs_type, status, reservering, gekozen, volgorde, tijd_van, tijd_tot, bijgewerkt_door)
  values (
    coalesce(v_id, gen_random_uuid()), p_item->>'dagdeel', p_item->>'titel', coalesce(p_item->>'omschrijving',''), coalesce(p_item->>'link',''), coalesce(p_item->>'adres',''),
    coalesce((p_item->>'prijs')::numeric, 0), coalesce(p_item->>'prijs_type','pp'), coalesce(p_item->>'status','geschat'),
    nullif(p_item->>'reservering',''),
    coalesce((p_item->>'dagdeel') = 'vast', false),
    coalesce((select max(volgorde)+1 from weekend.items where dagdeel = p_item->>'dagdeel'), 0),
    nullif(p_item->>'tijd_van','')::time, nullif(p_item->>'tijd_tot','')::time,
    left(coalesce(p_door,''), 40))
  returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.weekend_boodschap_opslaan(p_code text, p_item jsonb, p_door text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r weekend.boodschappen; v_id uuid := nullif(p_item->>'id','')::uuid; v_lijst text := coalesce(nullif(p_item->>'lijst',''),'boodschappen');
begin
  perform weekend.controleer(p_code);
  if v_id is not null then
    update weekend.boodschappen set
      naam = coalesce(p_item->>'naam', naam),
      hoeveelheid = coalesce(p_item->>'hoeveelheid', hoeveelheid),
      categorie = coalesce(p_item->>'categorie', categorie),
      wie = coalesce(p_item->>'wie', wie),
      prijs = case when p_item ? 'prijs' then nullif(p_item->>'prijs','')::numeric else prijs end,
      afgevinkt = coalesce((p_item->>'afgevinkt')::boolean, afgevinkt),
      bijgewerkt_door = left(coalesce(p_door,''), 40)
    where id = v_id
    returning * into r;
    if r.id is not null then return to_jsonb(r); end if;
    if not (p_item ? 'naam') then raise exception 'Regel niet gevonden'; end if;
  end if;
  insert into weekend.boodschappen (id, lijst, naam, hoeveelheid, categorie, wie, prijs, afgevinkt, volgorde, bijgewerkt_door)
  values (coalesce(v_id, gen_random_uuid()), v_lijst, p_item->>'naam', coalesce(p_item->>'hoeveelheid',''),
          coalesce(p_item->>'categorie','overig'), coalesce(p_item->>'wie',''),
          nullif(p_item->>'prijs','')::numeric, coalesce((p_item->>'afgevinkt')::boolean, false),
          coalesce((select max(volgorde)+1 from weekend.boodschappen where lijst = v_lijst and categorie = coalesce(p_item->>'categorie','overig')), 1),
          left(coalesce(p_door,''), 40))
  returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.weekend_taak_opslaan(p_code text, p_item jsonb, p_door text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r weekend.taken; v_id uuid := nullif(p_item->>'id','')::uuid;
begin
  perform weekend.controleer(p_code);
  if v_id is not null then
    update weekend.taken set
      titel = coalesce(p_item->>'titel', titel),
      deadline = case when p_item ? 'deadline' then nullif(p_item->>'deadline','')::date else deadline end,
      wie = coalesce(p_item->>'wie', wie),
      klaar = coalesce((p_item->>'klaar')::boolean, klaar),
      bijgewerkt_door = left(coalesce(p_door,''), 40)
    where id = v_id returning * into r;
    if r.id is not null then return to_jsonb(r); end if;
    if not (p_item ? 'titel') then raise exception 'Taak niet gevonden'; end if;
  end if;
  insert into weekend.taken (id, titel, deadline, wie, klaar, bijgewerkt_door)
  values (coalesce(v_id, gen_random_uuid()), p_item->>'titel', nullif(p_item->>'deadline','')::date, coalesce(p_item->>'wie',''),
          coalesce((p_item->>'klaar')::boolean, false), left(coalesce(p_door,''), 40))
  returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.weekend_uitgave_opslaan(p_code text, p_item jsonb, p_door text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r weekend.uitgaven; v_voor uuid[]; v_id uuid := nullif(p_item->>'id','')::uuid;
begin
  perform weekend.controleer(p_code);
  v_voor := case when p_item ? 'voor' then coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(p_item->'voor') x), '{}') else null end;
  if v_id is not null then
    update weekend.uitgaven set
      omschrijving = coalesce(p_item->>'omschrijving', omschrijving),
      bedrag = coalesce((p_item->>'bedrag')::numeric, bedrag),
      betaald_door = coalesce((p_item->>'betaald_door')::uuid, betaald_door),
      voor = coalesce(v_voor, voor),
      bon = case when p_item ? 'bon' then nullif(p_item->>'bon','') else bon end,
      bijgewerkt_door = left(coalesce(p_door,''), 40)
    where id = v_id returning * into r;
    if r.id is null then
      if not (p_item ? 'omschrijving' and p_item ? 'bedrag' and p_item ? 'betaald_door') then raise exception 'Uitgave niet gevonden'; end if;
    else
      return (to_jsonb(r) - 'bon') || jsonb_build_object('heeft_bon', r.bon is not null);
    end if;
  end if;
  insert into weekend.uitgaven (id, omschrijving, bedrag, betaald_door, voor, bon, bijgewerkt_door)
  values (coalesce(v_id, gen_random_uuid()), p_item->>'omschrijving', (p_item->>'bedrag')::numeric, (p_item->>'betaald_door')::uuid, coalesce(v_voor, '{}'),
          nullif(p_item->>'bon',''), left(coalesce(p_door,''), 40))
  returning * into r;
  return (to_jsonb(r) - 'bon') || jsonb_build_object('heeft_bon', r.bon is not null);
end $$;

-- 5. Rechten
do $$
declare f text;
begin
  foreach f in array array['public.weekend_versie(text)', 'public.weekend_kies_zet(text, uuid, boolean, text)']
  loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
    execute format('comment on function %s is %L', f, 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.');
  end loop;
end $$;

notify pgrst, 'reload schema';
