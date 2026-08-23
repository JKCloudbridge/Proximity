-- Sprint 0/1: extensions this project relies on throughout.
-- postgis powers every "shops/riders near you" query (§4.4/§4.7 of the
-- sprint plan). pg_cron drives the Organizer reminder job (Sprint 11).
-- pg_net is the fire-and-forget internal-webhook mechanism, same pattern
-- Baker Ally proved out for its restock-notify trigger -- reused here for
-- the Organizer reminder job and any future async notify hooks.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;
