-- Verwijdert de weekendplanner volledig uit het Supabase-project.
-- Daarna is het project weer precies zoals vóór setup.sql.
drop function if exists public.weekend_lijst(text);
drop function if exists public.weekend_opslaan(text, jsonb, text);
drop function if exists public.weekend_kies(text, uuid, text);
drop function if exists public.weekend_verwijder(text, uuid);
drop schema if exists weekend cascade;
