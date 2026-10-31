-- Verwijdert de weekendplanner volledig uit het Supabase-project.
-- Daarna is het project weer precies zoals vóór setup.sql.
drop function if exists public.weekend_lijst(text);
drop function if exists public.weekend_opslaan(text, jsonb, text);
drop function if exists public.weekend_kies(text, uuid, text);
drop function if exists public.weekend_verwijder(text, uuid);
drop function if exists public.weekend_boodschappen(text);
drop function if exists public.weekend_boodschap_opslaan(text, jsonb, text);
drop function if exists public.weekend_boodschap_verwijder(text, uuid);
drop function if exists public.weekend_boodschap_volgorde(text, jsonb);
drop function if exists public.weekend_kosten(text);
drop function if exists public.weekend_deelnemer_opslaan(text, jsonb);
drop function if exists public.weekend_deelnemer_verwijder(text, uuid);
drop function if exists public.weekend_uitgave_opslaan(text, jsonb, text);
drop function if exists public.weekend_uitgave_verwijder(text, uuid);
drop function if exists public.weekend_bon(text, uuid);
drop function if exists public.weekend_taken(text);
drop function if exists public.weekend_taak_opslaan(text, jsonb, text);
drop function if exists public.weekend_taak_verwijder(text, uuid);
drop function if exists public.weekend_instellingen(text);
drop function if exists public.weekend_instelling_opslaan(text, text, text);
drop schema if exists weekend cascade;
