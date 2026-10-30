-- =====================================================================
-- Vriendenweekend Brugge: update 3
-- Tab "Meenemen": een tweede lijst in dezelfde tabel, met eigen soorten,
-- meteen gevuld met suggesties. Alleen toevoegingen; de boodschappen
-- blijven staan. Eén keer draaien in de SQL Editor.
-- =====================================================================

alter table weekend.boodschappen
  add column if not exists lijst text not null default 'boodschappen';
alter table weekend.boodschappen drop constraint if exists boodschappen_lijst_check;
alter table weekend.boodschappen add constraint boodschappen_lijst_check check (lijst in ('boodschappen','meenemen'));

alter table weekend.boodschappen drop constraint if exists boodschappen_categorie_check;
alter table weekend.boodschappen add constraint boodschappen_categorie_check check (categorie in (
  'ontbijt','lunch','diner','drank','snacks',
  'papieren','spelletjes','keuken','slapen','persoonlijk','auto',
  'overig'));

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
    insert into weekend.boodschappen (lijst, naam, hoeveelheid, categorie, wie, prijs, bijgewerkt_door)
    values (coalesce(nullif(p_item->>'lijst',''),'boodschappen'), p_item->>'naam', coalesce(p_item->>'hoeveelheid',''),
            coalesce(p_item->>'categorie','overig'), coalesce(p_item->>'wie',''),
            nullif(p_item->>'prijs','')::numeric, left(coalesce(p_door,''), 40))
    returning * into r;
  end if;
  return to_jsonb(r);
end $$;

-- Suggesties voor de meeneemlijst (alleen als die nog leeg is)
insert into weekend.boodschappen (lijst, naam, hoeveelheid, categorie, bijgewerkt_door, toegevoegd_op)
select 'meenemen', v.naam, v.hv, v.cat, 'Claude', now() + (v.n || ' seconds')::interval
from (values
  (1,'ID-kaart of paspoort (verplicht bij je in België)','iedereen','papieren'),
  (2,'Bankpas en wat contant geld (sommige Brugse cafés: alleen cash)','iedereen','papieren'),
  (3,'Boekingsbevestiging huisje + sleutelinstructies','1×','papieren'),
  (4,'Rijbewijs, kentekenbewijs en groene kaart','per auto','auto'),
  (5,'Veiligheidshesje en gevarendriehoek','per auto','auto'),
  (6,'LEZ-registratie als je door Gent of Antwerpen rijdt (gratis, vooraf online)','per auto','auto'),
  (7,'Koelbox met koelelementen (dinerbox en bier)','2','auto'),
  (8,'Hitster (eigen variant) met kaartjes','1×','spelletjes'),
  (9,'Nintendo Switch + 4 controllers + HDMI-kabel','1×','spelletjes'),
  (10,'Dartbord en pijlen (als het huisje er geen heeft)','1×','spelletjes'),
  (11,'Bluetooth-speaker + gedeelde playlist','1×','spelletjes'),
  (12,'Speelkaarten en pokerset','1×','spelletjes'),
  (13,'Spullen voor het gekozen spel van zaterdagavond','zie planning','spelletjes'),
  (14,'Flesopener en kurkentrekker','2 + 1','keuken'),
  (15,'Bakpapier en aluminiumfolie','1 rol van elk','keuken'),
  (16,'Keukenrol, theedoeken en vaatwastabletten','paar van elk','keuken'),
  (17,'Vuilniszakken','1 rol','keuken'),
  (18,'Scherp koksmes (huisjesmessen zijn vaak bot)','1','keuken'),
  (19,'Beddengoed en handdoeken (checken of het huisje die heeft)','per persoon','slapen'),
  (20,'Oordopjes (snurkers…)','per persoon','slapen'),
  (21,'Slippers of sloffen','per persoon','slapen'),
  (22,'Toilettas en medicijnen','per persoon','persoonlijk'),
  (23,'Telefoonoplader en powerbank','per persoon','persoonlijk'),
  (24,'Wandelschoenen en regenjas (zaterdagochtend)','per persoon','persoonlijk'),
  (25,'Warme trui of jas voor ''s avonds','per persoon','persoonlijk'),
  (26,'EHBO-setje: paracetamol, Rennies, pleisters','1×','persoonlijk'),
  (27,'Stekkerdoos of verlengsnoer','1','overig')
) as v(n, naam, hv, cat)
where not exists (select 1 from weekend.boodschappen where lijst = 'meenemen');

notify pgrst, 'reload schema';
