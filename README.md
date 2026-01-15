# Jellyserver

Automated media server stack with Jellyfin, *arr apps, and auto HEVC transcoding.

## Quick Start (Docker)

```bash
./jellyfin.sh
```

## What's Included

| Service | Port | Purpose |
|---------|------|---------|
| Jellyfin | 8020 | Media server - watch here |
| Jellyseerr | 8025 | Request UI - search & request here |
| Radarr | 8023 | Movie management |
| Sonarr | 8024 | TV show management |
| Prowlarr | 8022 | Indexer manager |
| Transmission | 8021 | Torrent client (admin/mediastack) |
| Tdarr | 8029 | Auto HEVC transcoding |

## Features

- **Auto-configured** - API keys, download clients, root folders set up automatically
- **16 indexers** - YTS, EZTV, TPB, Nyaa.si, and more for movies, TV, anime
- **HEVC preference** - Custom format created to prefer x265/HEVC releases
- **Auto transcoding** - Tdarr converts existing files to HEVC
- **Idempotent** - Safe to re-run, preserves config

## Manual Steps After First Run

1. **Jellyfin** (http://localhost:8020)
   - Create admin account
   - Add libraries: Movies=/media/movies, Shows=/media/shows

2. **Jellyseerr** (http://localhost:8025)
   - Sign in with Jellyfin account
   - Settings > Services > Add Radarr (http://radarr:7878)
   - Settings > Services > Add Sonarr (http://sonarr:8989)
   - API keys are printed after script runs (also in ~/jellyfin/.api_keys)

3. **Tdarr** (http://localhost:8029)
   - Add library pointing to /media/Movies or /media/Shows
   - Configure transcode flow with HEVC output

## NixOS Module

For NixOS users, `flake.nix` provides a declarative module using [declarative-jellyfin](https://github.com/Sveske-Juice/declarative-jellyfin).

```nix
{
  inputs.jellyserver.url = "github:kanielrkirby/jellyserver";
  
  outputs = { jellyserver, ... }: {
    nixosConfigurations.myhost = {
      modules = [ jellyserver.nixosModules.default ];
    };
  };
}
```

## Directory Structure

```
~/jellyfin/           # Config data
~/Movies/Jellyfin/    # Media files
  ├── Movies/
  └── Shows/
~/Downloads/torrents/ # Download location
```

## Indexers

Movies & TV: YTS, EZTV, LimeTorrents, ThePirateBay, TorrentDownloads, BitSearch, MoviesDVDR, Rutor, BigFanGroup, EliteTorrent

Anime: Nyaa.si, TokyoTosho, Mikan, AcgRip, DMHY, ShanaProject
