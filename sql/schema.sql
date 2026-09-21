-- Reconstructed from the queries in playbooks/templates/*.py.j2.
-- The live databases were created by hand; this is the minimum those
-- scripts need. Grant each role only what it uses.

-- ---------------------------------------------------------------------
-- radio_metadata: library index written by scan-music-metadata.py (NAS),
-- read by build-smart-playlist.py (NAS).
-- ---------------------------------------------------------------------
-- CREATE DATABASE radio_metadata;
-- \c radio_metadata
CREATE TABLE IF NOT EXISTS tracks (
    filepath          TEXT PRIMARY KEY,
    artist            TEXT,
    title             TEXT,
    album             TEXT,
    genre             TEXT,
    track_number      INTEGER,
    duration_seconds  DOUBLE PRECISION,
    file_modified     TIMESTAMP,
    last_scanned      TIMESTAMP
);
CREATE INDEX IF NOT EXISTS tracks_genre_lower_idx ON tracks (LOWER(genre));

-- ---------------------------------------------------------------------
-- radio_spins: play log written by log-spin.py (radio host), read by the
-- spin tracker (radio host) and by build-smart-playlist.py (NAS).
-- ---------------------------------------------------------------------
-- CREATE DATABASE radio_spins;
-- \c radio_spins
CREATE TABLE IF NOT EXISTS spins (
    id         BIGSERIAL PRIMARY KEY,
    artist     TEXT,
    title      TEXT,
    album      TEXT,
    show_name  TEXT,
    filepath   TEXT,
    played_at  TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS spins_played_at_idx ON spins (played_at);

-- Roles used by the scripts:
--   radio_app      (radio host)  INSERT/SELECT on radio_spins.spins
--   radio_indexer  (NAS)         ALL on radio_metadata.tracks, SELECT on radio_spins.spins
