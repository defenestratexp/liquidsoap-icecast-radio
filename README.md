# liquidsoap-icecast-radio

A self-hosted internet radio station built from Icecast and Liquidsoap, deployed
with Ansible. It plays a personal music library as a schedule of genre "shows",
with spoken between-song DJ breaks generated locally by
[Piper TTS](https://github.com/rhasspy/piper), a Postgres-backed play log, and a
small installable web player.

This is a personal, non-commercial project from a working homelab. It streams
the owner's own library to their own devices. Nothing here licenses or supplies
music. Host names, addresses and credentials are placeholders.

## Architecture

```
            NAS (music library, NFS)                         Postgres
  ┌──────────────────────────────────────┐            ┌──────────────────┐
  │ cron */4h generate-show-playlists.sh │──upsert──► │ radio_metadata   │
  │   scan-music-metadata.py (mutagen)   │            │   .tracks        │
  │   build-smart-playlist.py per show ──┼──read────► │ radio_spins      │
  │   => /mnt/media/radio-shows/*.m3u    │            │   .spins         │
  └───────────────┬──────────────────────┘            └────────▲─────────┘
                  │ NFS (ro): music + show playlists             │ insert
  ┌───────────────▼──────────────────────────────────────────────┴──────┐
  │ radio host                                                           │
  │  cron */5m show-scheduler.sh ─ picks the show for this hour, copies │
  │     its m3u to library.m3u, telnet "music.reload", renders a TTS    │
  │     show intro                                                       │
  │  Liquidsoap radio.liq ─ random playlist + announcement queue        │
  │     every 5 tracks ─► dj-announce.sh ─► Piper ─► mp3 ─► queue       │
  │     on_end ─► log-spin.py ─► Postgres; now_playing.json             │
  │  Icecast2 :8000  /stream  + player.html, schedule.html, PWA files   │
  │  spin-tracker.py (Flask :5000) ─ top 50 / recent / search           │
  └──────────────────────────────────────────────────────────────────────┘
```

### The DJ

The DJ breaks are **fixed template text, spoken by Piper TTS**. Liquidsoap
writes the last three tracks' tags to a file every five songs;
`dj-announce.sh` fills fixed sentence templates ("From the album X by Y, that
was Z. Before that ... Next up ...") and adds a sign-off with the show's DJ
persona. The next track comes from Liquidsoap's telnet `music.next`, read with
`ffprobe`. Piper renders the text to WAV using the persona's voice model, and
ffmpeg converts it to 44.1 kHz/128k MP3 to match the stream. Liquidsoap then
plays it between tracks from a `request.queue`. The personas are fictional
names mapped to stock Piper voices in `dj-config.sh.j2`.

### Playlist rules

`build-smart-playlist.py` builds each show's m3u from the metadata DB by genre.
Its rules:

- de-duplicate by (artist, title)
- cap tracks per artist (30) and per (artist, album) (5), so compilations are
  not starved
- exclude anything played in the last 12 h
- weight by 7-day spin count, so less-played tracks surface first
- boost tracks added in the last 7 days

The scanner is incremental by mtime, normalises genre spellings, and supports
per-folder genre overrides for consistently mis-tagged artists.
`audit-show-playlists.sh` reports tracks whose genre does not belong in their
show.

## Usage

```bash
ansible-galaxy collection install -r requirements.yml
cp inventory.example.ini inventory.ini                      # edit
cp secrets/radio/vault.yml.example secrets/radio/vault.yml  # edit, then:
ansible-vault encrypt secrets/radio/vault.yml
$EDITOR playbooks/group_vars/all.yml                        # station name, hosts

psql -h <db-host> -f sql/schema.sql   # once per database; see comments inside

ansible-playbook -i inventory.ini playbooks/radio_server.yml --ask-vault-pass
ansible-playbook -i inventory.ini playbooks/radio_shows.yml  --ask-vault-pass
```

Database passwords are fetched from AWS Secrets Manager by
`roles/homelab_secret_fetch` (`homelab/postgresql/radio`,
`homelab/postgresql/radio-indexer`, each JSON with a `password` key). This needs
the `amazon.aws` collection and AWS credentials on the control node. To use
another secret source, swap that role for a vault variable.

Optional PWA icons: put `icon-192.png` and `icon-512.png` in `playbooks/files/`.

To change the schedule, edit the show hours in `show-scheduler.sh.j2`, the genre
sets in `generate-show-playlists.sh.j2` and `audit-show-playlists.sh.j2`, the
personas in `dj-config.sh.j2`, and the display copy in `radio-player.html.j2`
and `radio-schedule.html.j2`. They are kept in sync by hand.

## Layout

```
playbooks/
  radio_server.yml        Icecast, Liquidsoap, Piper + voices, player, spin tracker
  radio_shows.yml         NAS-side scanner/playlist builder + radio-side scheduler
  group_vars/all.yml      station identity and host placeholders
  templates/
    radio.liq.j2                     Liquidsoap script
    icecast.xml.j2, liquidsoap.service.j2
    dj-config.sh.j2, dj-announce.sh.j2, show-scheduler.sh.j2
    scan-music-metadata.py.j2, build-smart-playlist.py.j2,
    generate-show-playlists.sh.j2, audit-show-playlists.sh.j2
    log-spin.py.j2, spin-tracker.py.j2, spin-tracker.service.j2
    radio-player.html.j2, radio-schedule.html.j2, radio-manifest.json.j2, radio-sw.js.j2
roles/homelab_secret_fetch/  AWS Secrets Manager lookup -> fact
secrets/radio/vault.yml.example
sql/schema.sql            tables the scripts expect (reconstructed)
inventory.example.ini, ansible.cfg, requirements.yml
```

## Requirements

- Radio host: Debian/Ubuntu with systemd (icecast2, liquidsoap, ffmpeg,
  python3-flask, python3-psycopg2 are installed by the playbook). x86_64 for the
  bundled Piper binary.
- NAS: exports the library over NFS; runs Python 3 with psycopg2 and mutagen
  (installed by the playbook).
- PostgreSQL reachable from both hosts.
- Ansible with `ansible.posix`, `amazon.aws` (plus boto3 on the control node).
- MP3 files with reasonable ID3 tags (artist/title/album/genre).

## Notes and limits

- The stream mount is `public=false` and is not listed in any directory. Put
  authentication in front of it (or keep it on the LAN) unless you hold the
  rights to broadcast your library.
- The Liquidsoap telnet server binds to 127.0.0.1 only.
- The spin tracker is served by Flask's built-in server on :5000. The player
  links to `/stats/`, which assumes a reverse proxy maps `/stats/` to it.

## License

MIT. See [LICENSE](LICENSE).
