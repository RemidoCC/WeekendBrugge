-- =====================================================================
-- Vriendenweekend Brugge — planner (TIJDELIJK)
-- Draai dit één keer in de SQL Editor van het Supabase-project.
-- Alles staat in een eigen schema "weekend" plus vier functies
-- public.weekend_*; bestaande tabellen worden niet aangeraakt.
-- Opruimen na het weekend: opruimen.sql
--
-- LET OP: vervang onderaan 'VUL-HIER-DE-TOEGANGSCODE-IN' door de
-- toegangscode voordat je dit script draait.
-- =====================================================================

create schema weekend;
comment on schema weekend is 'TIJDELIJK: Vriendenweekend Brugge (planner). Staat los van de rest. Na 15-11-2026 verwijderen met opruimen.sql.';
revoke all on schema weekend from public, anon, authenticated;

create table weekend.config (
  id int primary key default 1 check (id = 1),
  code_hash text not null
);

create table weekend.items (
  id uuid primary key default gen_random_uuid(),
  dagdeel text not null check (dagdeel in ('vast','vr-middag','vr-avond','vr-laat','za-ochtend','za-lunch','za-middag','za-avond','za-nacht','zo-ochtend','zo-wandeling','zo-lunch')),
  titel text not null check (length(titel) between 1 and 120),
  omschrijving text not null default '' check (length(omschrijving) <= 1000),
  link text not null default '' check (length(link) <= 500),
  prijs numeric(10,2) not null default 0 check (prijs >= 0 and prijs < 100000),
  prijs_type text not null default 'pp' check (prijs_type in ('pp','totaal')),
  status text not null default 'geschat' check (status in ('geschat','bevestigd')),
  gekozen boolean not null default false,
  volgorde int not null default 0,
  bijgewerkt_op timestamptz not null default now(),
  bijgewerkt_door text not null default '' check (length(bijgewerkt_door) <= 40)
);
alter table weekend.config enable row level security;
alter table weekend.items enable row level security;
revoke all on all tables in schema weekend from public, anon, authenticated;

create function weekend.controleer(p_code text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_code is null or not exists (
    select 1 from weekend.config c where c.code_hash = extensions.crypt(p_code, c.code_hash)
  ) then
    raise exception 'Onjuiste toegangscode' using errcode = '28000';
  end if;
end $$;
revoke all on function weekend.controleer(text) from public, anon, authenticated;

create function public.weekend_lijst(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  return coalesce((select jsonb_agg(to_jsonb(i) order by i.dagdeel, i.volgorde, i.bijgewerkt_op) from weekend.items i), '[]'::jsonb);
end $$;

create function public.weekend_opslaan(p_code text, p_item jsonb, p_door text) returns jsonb
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
      bijgewerkt_op = now(),
      bijgewerkt_door = left(coalesce(p_door,''), 40)
    where id = (p_item->>'id')::uuid
    returning * into r;
    if r.id is null then raise exception 'Optie niet gevonden'; end if;
  else
    insert into weekend.items (dagdeel, titel, omschrijving, link, prijs, prijs_type, status, gekozen, volgorde, bijgewerkt_door)
    values (
      p_item->>'dagdeel', p_item->>'titel', coalesce(p_item->>'omschrijving',''), coalesce(p_item->>'link',''),
      coalesce((p_item->>'prijs')::numeric, 0), coalesce(p_item->>'prijs_type','pp'), coalesce(p_item->>'status','geschat'),
      coalesce((p_item->>'dagdeel') = 'vast', false),
      coalesce((select max(volgorde)+1 from weekend.items where dagdeel = p_item->>'dagdeel'), 0),
      left(coalesce(p_door,''), 40))
    returning * into r;
  end if;
  return to_jsonb(r);
end $$;

create function public.weekend_kies(p_code text, p_id uuid, p_door text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_dagdeel text; v_gekozen boolean;
begin
  perform weekend.controleer(p_code);
  select dagdeel, gekozen into v_dagdeel, v_gekozen from weekend.items where id = p_id;
  if v_dagdeel is null then raise exception 'Optie niet gevonden'; end if;
  if v_dagdeel <> 'vast' and not v_gekozen then
    update weekend.items set gekozen = false where dagdeel = v_dagdeel and gekozen;
  end if;
  update weekend.items set gekozen = not v_gekozen, bijgewerkt_op = now(), bijgewerkt_door = left(coalesce(p_door,''),40) where id = p_id;
end $$;

create function public.weekend_verwijder(p_code text, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform weekend.controleer(p_code);
  delete from weekend.items where id = p_id;
end $$;

revoke all on function public.weekend_lijst(text) from public;
revoke all on function public.weekend_opslaan(text, jsonb, text) from public;
revoke all on function public.weekend_kies(text, uuid, text) from public;
revoke all on function public.weekend_verwijder(text, uuid) from public;
grant execute on function public.weekend_lijst(text) to anon, authenticated;
grant execute on function public.weekend_opslaan(text, jsonb, text) to anon, authenticated;
grant execute on function public.weekend_kies(text, uuid, text) to anon, authenticated;
grant execute on function public.weekend_verwijder(text, uuid) to anon, authenticated;

comment on function public.weekend_lijst(text) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';
comment on function public.weekend_opslaan(text, jsonb, text) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';
comment on function public.weekend_kies(text, uuid, text) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';
comment on function public.weekend_verwijder(text, uuid) is 'TIJDELIJK: Vriendenweekend Brugge. Verwijderen met opruimen.sql.';

-- ---------------------------------------------------------------------
-- Startopties (prijzen: 'pp' = per persoon, 'totaal' = voor de groep)
-- ---------------------------------------------------------------------
insert into weekend.items (dagdeel, titel, omschrijving, link, prijs, prijs_type, status, gekozen, volgorde) values
-- Vaste posten (tellen mee zolang ze aan staan)
('vast','Brandstof, 2 auto''s','Sevenum – Beernem v.v. plus ritjes ter plekke, ca. 500 km per auto.','',140,'totaal','geschat',true,0),
('vast','Ontbijt 2× (boodschappen)','Zaterdag en zondag, zelf ontbijten in het huisje.','',100,'totaal','geschat',true,1),
('vast','Drank & snacks voor het huisje','Bier, wijn, fris en borrelhapjes voor vrijdag- en zaterdagavond.','',150,'totaal','geschat',true,2),
('vast','Parkeren Brugge (zaterdag)','Twee auto''s, bij voorkeur een randparking met pendelbus.','',25,'totaal','geschat',true,3),
('vast','Taxi Brugge → Beernem (zaterdagnacht)','Na het stappen niemand achter het stuur. Ca. 15 km, busje voor 7.','',70,'totaal','geschat',true,4),
-- Vrijdag
('vr-middag','Doorrijden, broodjes mee','Thuis smeren en onderweg eten, zo vroeg mogelijk in het huisje.','',0,'pp','bevestigd',false,0),
('vr-middag','Lunch onderweg','Stop bij een wegrestaurant rond Antwerpen.','',15,'pp','geschat',false,1),
('vr-avond','Dinerbox "Cook like a chef"','4 gangen van sterrenrestaurants (o.a. De Librije, De Leest). Volledig voorbereid, alleen afmaken. Bezorging alleen in NL op vr/za: vrijdagochtend in Sevenum laten bezorgen en in de koelbox mee. Plus bezorgkosten.','https://www.maaltijdbox.com/cook-like-a-chef/',69.50,'pp','bevestigd',false,0),
('vr-avond','Privékok in het huisje (Take a Chef)','Kok kookt 4 gangen in het huisje en ruimt op. Gemiddeld ca. €73 p.p. bij 7–12 gasten, excl. drank.','https://www.takeachef.com/en-be/private-chef/provincie-west-vlaanderen',73,'pp','geschat',false,1),
('vr-avond','Traiteur uit Brugge (Madam Traiteur)','Menu op maat vanaf 8 personen, vrijblijvende offerte aanvragen. Prijs is een gok.','https://madamtraiteur.be/',45,'pp','geschat',false,2),
('vr-laat','Hitster-avond','Eigen Hitster-variant mee; aan tafel na het dessert.','',0,'pp','bevestigd',false,0),
('vr-laat','Pubquiz','Zelf een quiz maken over de vriendengroep en België.','',0,'pp','bevestigd',false,1),
('vr-laat','Belgische bierproeverij in het huisje','Zelf een proefplank samenstellen met tripels, kriek en geuze.','',10,'pp','geschat',false,2),
-- Zaterdag
('za-ochtend','Uitslapen en uitgebreid ontbijt','Rustig opstarten; ontbijt valt onder de vaste posten.','',0,'pp','bevestigd',false,0),
('za-ochtend','Kort rondje Bulskampveld','Frisse neus in het kasteelpark, vlakbij het huisje.','https://www.eghn.org/en/castle-park-bulskampveld/',0,'pp','bevestigd',false,1),
('za-lunch','Frietjes en broodje in Brugge','Snel en goedkoop tussen de bezienswaardigheden door.','',12,'pp','geschat',false,0),
('za-lunch','Lunch in een brasserie','Zitten, bijkletsen, eerste biertje.','',25,'pp','geschat',false,1),
('za-middag','Brouwerij De Halve Maan – klassiek','Rondleiding van ca. 45 min, inclusief één bier.','https://www.halvemaan.be/en/visit/brewery',16,'pp','bevestigd',false,0),
('za-middag','Brouwerij De Halve Maan – XL','Ca. 90 min, proeverij van drie bieren in de kelders. Alleen in het weekend.','https://www.halvemaan.be/en/visit/brewery',26,'pp','bevestigd',false,1),
('za-middag','Rondvaart op de reien (onder voorbehoud)','Ca. 30 min. Boten varen tot half november; op 14 nov niet zeker. Prijs is een schatting.','https://bezoekers.brugge.be/en/bruggemetdeboot',15,'pp','geschat',false,2),
('za-middag','Vrij rondstruinen door de binnenstad','Markt, Burg, Rozenhoedkaai, Begijnhof – gratis.','',0,'pp','bevestigd',false,3),
('za-avond','Stoofvlees van de traiteur in het huisje','Simpel en Belgisch; opwarmen en klaar. Prijs is een schatting.','',20,'pp','geschat',false,0),
('za-avond','Zelf koken: mosselen met friet','Samen koken in het huisje.','',15,'pp','geschat',false,1),
('za-avond','Bistro in Brugge (Vlaamse keuken)','Bijvoorbeeld stoofvlees of waterzooi; reserveren voor 7. Incl. een drankje, geschat.','',45,'pp','geschat',false,2),
('za-nacht','Bierkroegentocht door Brugge','De Garre → ''t Brugs Beertje → Le Trappiste (kelder uit de 13e eeuw) → Café Vlissinghe.','https://jetsettingfools.com/best-beer-bars-in-bruges-belgium/',30,'pp','geschat',false,0),
('za-nacht','Bieratelier: proefplank met 12 bieren','Levendige kroeg; bieren zijn aan de prijzige kant.','https://jetsettingfools.com/best-beer-bars-in-bruges-belgium/',25,'pp','geschat',false,1),
('za-nacht','Doordrinken in het huisje','Drank valt onder de vaste posten (taxi dan uitzetten).','',0,'pp','bevestigd',false,2),
-- Zondag
('zo-ochtend','Ontbijt, opruimen en uitchecken','Rustig aan; ontbijt valt onder de vaste posten.','',0,'pp','bevestigd',false,0),
('zo-wandeling','Bulskampveld-wandelroute (9,4 km)','Ca. 2,5 uur langs het kasteel en de heidevelden, in Beernem zelf. Start: parking Driekoningen.','https://uploads-ssl.webflow.com/606186a0ab3823e1e172792c/61a6550dba454853bf6e78f7_bulskampveldwandelroute.pdf',0,'pp','bevestigd',false,0),
('zo-wandeling','Damme – Damse Vaart (11,8 km)','Lus vanaf de markt van Damme, langs de vaart en het kasteel van Oostkerke.','https://www.ich-geh-wandern.de/wanderroute-damse-vaart-entlang-des-damme-kanals',0,'pp','bevestigd',false,1),
('zo-lunch','Theeschenkerij bij kasteel Bulskampveld','Na de wandeling; terras en gratis parkeren. Prijs is een schatting.','https://www.eghn.org/en/castle-park-bulskampveld/',18,'pp','geschat',false,0),
('zo-lunch','Restaurant aan de Damse Vaart','Lunch met uitzicht op het water, na de wandeling bij Damme.','https://www.ich-geh-wandern.de/wanderroute-damse-vaart-entlang-des-damme-kanals',25,'pp','geschat',false,1);

-- ---------------------------------------------------------------------
-- Toegangscode (vervang de tekst tussen de quotes!)
-- ---------------------------------------------------------------------
insert into weekend.config (id, code_hash)
values (1, extensions.crypt('VUL-HIER-DE-TOEGANGSCODE-IN', extensions.gen_salt('bf')));
