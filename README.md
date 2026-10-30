# Vriendenweekend Brugge

Planner voor het vriendenweekend in Beernem (13–15 november 2026): per dagdeel opties kiezen, zelf opties toevoegen, en een live budgetoverzicht (€300 p.p., 7 personen, huisje €720 al geboekt).

- `index.html`: de pagina (GitHub Pages).
- `setup.sql`: maakt de opslag aan in Supabase. Het gebruikt een eigen schema `weekend` en vier functies `public.weekend_*`, en raakt verder niets. De toegangscode staat er bewust niet in; vul hem onderaan in voordat je het script draait.
- `update-2.sql`: meerdere keuzes per dagdeel, tijden bij activiteiten en de boodschappenlijst. Eén keer draaien na `setup.sql`.
- `update-3.sql`: tab Meenemen, meteen gevuld met suggesties. Eén keer draaien na `update-2.sql`.
- `opruimen.sql`: haalt na het weekend alles weer weg.

Lezen en schrijven kan alleen met de toegangscode. De pagina vraagt die één keer en onthoudt hem in de browser.
