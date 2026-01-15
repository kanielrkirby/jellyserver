#!/usr/bin/env bash
set -e

BASE_DIR="$HOME/jellyfin"
MEDIA_DIR="$HOME/Movies/Jellyfin"
DOWNLOADS_DIR="$HOME/Downloads/torrents"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Generate deterministic API keys (or reuse existing)
KEYS_FILE="$BASE_DIR/.api_keys"
if [[ -f "$KEYS_FILE" ]]; then
  source "$KEYS_FILE"
else
  RADARR_KEY=$(nix run nixpkgs#openssl -- rand -hex 16)
  SONARR_KEY=$(nix run nixpkgs#openssl -- rand -hex 16)
  PROWLARR_KEY=$(nix run nixpkgs#openssl -- rand -hex 16)
fi

mkdir -p "$BASE_DIR"/{jellyfin/config,radarr,sonarr,prowlarr,qbittorrent/qBittorrent,jellyseerr}
mkdir -p "$MEDIA_DIR"/{Shows,Movies}
mkdir -p "$DOWNLOADS_DIR"

# Save keys for reuse
cat > "$KEYS_FILE" << EOF
RADARR_KEY=$RADARR_KEY
SONARR_KEY=$SONARR_KEY
PROWLARR_KEY=$PROWLARR_KEY
EOF

# Pre-configure Radarr
cat > "$BASE_DIR/radarr/config.xml" << EOF
<Config>
  <ApiKey>$RADARR_KEY</ApiKey>
  <Port>7878</Port>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <InstanceName>Radarr</InstanceName>
</Config>
EOF

# Pre-configure Sonarr
cat > "$BASE_DIR/sonarr/config.xml" << EOF
<Config>
  <ApiKey>$SONARR_KEY</ApiKey>
  <Port>8989</Port>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <InstanceName>Sonarr</InstanceName>
</Config>
EOF

# Pre-configure Prowlarr
cat > "$BASE_DIR/prowlarr/config.xml" << EOF
<Config>
  <ApiKey>$PROWLARR_KEY</ApiKey>
  <Port>9696</Port>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <InstanceName>Prowlarr</InstanceName>
</Config>
EOF

docker rm -f jellyfin radarr sonarr prowlarr transmission jellyseerr 2>/dev/null || true

# Create network for inter-container communication
docker network create mediastack 2>/dev/null || true

# Jellyfin - Media server
docker run -d \
  --name jellyfin \
  --network mediastack \
  --restart unless-stopped \
  -p 8020:8096 \
  -v "$BASE_DIR/jellyfin":/config \
  -v "$MEDIA_DIR/Movies":/media/movies \
  -v "$MEDIA_DIR/Shows":/media/shows \
  jellyfin/jellyfin:latest

# Transmission - Torrent client
docker run -d \
  --name transmission \
  --network mediastack \
  --restart unless-stopped \
  -p 8021:9091 \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  -e USER=admin \
  -e PASS=mediastack \
  -v "$BASE_DIR/transmission":/config \
  -v "$DOWNLOADS_DIR":/downloads \
  -v "$MEDIA_DIR":/media \
  lscr.io/linuxserver/transmission:latest

# Prowlarr - Indexer manager
docker run -d \
  --name prowlarr \
  --network mediastack \
  --restart unless-stopped \
  -p 8022:9696 \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  -v "$BASE_DIR/prowlarr":/config \
  lscr.io/linuxserver/prowlarr:latest

# Radarr - Movie management
docker run -d \
  --name radarr \
  --network mediastack \
  --restart unless-stopped \
  -p 8023:7878 \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  -v "$BASE_DIR/radarr":/config \
  -v "$MEDIA_DIR/Movies":/movies \
  -v "$DOWNLOADS_DIR":/downloads \
  lscr.io/linuxserver/radarr:latest

# Sonarr - TV show management
docker run -d \
  --name sonarr \
  --network mediastack \
  --restart unless-stopped \
  -p 8024:8989 \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  -v "$BASE_DIR/sonarr":/config \
  -v "$MEDIA_DIR/Shows":/tv \
  -v "$DOWNLOADS_DIR":/downloads \
  lscr.io/linuxserver/sonarr:latest

# Jellyseerr - Request UI
docker run -d \
  --name jellyseerr \
  --network mediastack \
  --restart unless-stopped \
  -p 8025:5055 \
  -v "$BASE_DIR/jellyseerr":/app/config \
  fallenbagel/jellyseerr:latest

echo "Waiting for services to start..."
sleep 10

# Configure Radarr via API
echo "Configuring Radarr..."
curl -s -X POST "http://localhost:8023/api/v3/rootfolder" \
  -H "X-Api-Key: $RADARR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"path": "/movies"}' > /dev/null 2>&1 || true

curl -s -X POST "http://localhost:8023/api/v3/downloadclient" \
  -H "X-Api-Key: $RADARR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Transmission",
    "implementation": "Transmission",
    "configContract": "TransmissionSettings",
    "protocol": "torrent",
    "priority": 1,
    "fields": [
      {"name": "host", "value": "transmission"},
      {"name": "port", "value": 9091},
      {"name": "username", "value": "admin"},
      {"name": "password", "value": "mediastack"},
      {"name": "movieCategory", "value": "radarr"}
    ],
    "enable": true
  }' > /dev/null 2>&1 || true

# Configure Sonarr via API
echo "Configuring Sonarr..."
curl -s -X POST "http://localhost:8024/api/v3/rootfolder" \
  -H "X-Api-Key: $SONARR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"path": "/tv"}' > /dev/null 2>&1 || true

curl -s -X POST "http://localhost:8024/api/v3/downloadclient" \
  -H "X-Api-Key: $SONARR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Transmission",
    "implementation": "Transmission",
    "configContract": "TransmissionSettings",
    "protocol": "torrent",
    "priority": 1,
    "fields": [
      {"name": "host", "value": "transmission"},
      {"name": "port", "value": 9091},
      {"name": "username", "value": "admin"},
      {"name": "password", "value": "mediastack"},
      {"name": "tvCategory", "value": "sonarr"}
    ],
    "enable": true
  }' > /dev/null 2>&1 || true

# Configure Prowlarr to sync with Radarr and Sonarr
echo "Configuring Prowlarr..."
curl -s -X POST "http://localhost:8022/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Radarr\",
    \"syncLevel\": \"fullSync\",
    \"implementation\": \"Radarr\",
    \"configContract\": \"RadarrSettings\",
    \"fields\": [
      {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:9696\"},
      {\"name\": \"baseUrl\", \"value\": \"http://radarr:7878\"},
      {\"name\": \"apiKey\", \"value\": \"$RADARR_KEY\"},
      {\"name\": \"syncCategories\", \"value\": [2000,2010,2020,2030,2040,2045,2050,2060]}
    ]
  }" > /dev/null 2>&1 || true

curl -s -X POST "http://localhost:8022/api/v1/applications" \
  -H "X-Api-Key: $PROWLARR_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Sonarr\",
    \"syncLevel\": \"fullSync\",
    \"implementation\": \"Sonarr\",
    \"configContract\": \"SonarrSettings\",
    \"fields\": [
      {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:9696\"},
      {\"name\": \"baseUrl\", \"value\": \"http://sonarr:8989\"},
      {\"name\": \"apiKey\", \"value\": \"$SONARR_KEY\"},
      {\"name\": \"syncCategories\", \"value\": [5000,5010,5020,5030,5040,5045,5050]}
    ]
  }" > /dev/null 2>&1 || true

# Add indexers to Prowlarr
echo "Adding indexers..."
for indexer in "yts" "eztv" "limetorrents" "thepiratebay"; do
  curl -s -X POST "http://localhost:8022/api/v1/indexer" \
    -H "X-Api-Key: $PROWLARR_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$indexer\",
      \"implementation\": \"Cardigann\",
      \"configContract\": \"CardigannSettings\",
      \"enable\": true,
      \"priority\": 25,
      \"appProfileId\": 1,
      \"fields\": [
        {\"name\": \"definitionFile\", \"value\": \"$indexer\"}
      ]
    }" > /dev/null 2>&1 || true
done

# Sync indexers to apps
curl -s -X POST "http://localhost:8022/api/v1/command" \
  -H "X-Api-Key: $PROWLARR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "ApplicationIndexerSync"}' > /dev/null 2>&1 || true

echo ""
echo "===== Media Stack Started ====="
echo ""
echo "Jellyseerr:  http://localhost:8025  <-- REQUEST MEDIA HERE"
echo "Jellyfin:    http://localhost:8020  <-- WATCH HERE"
echo ""
echo "Backend (already configured):"
echo "Transmission: http://localhost:8021 (admin/mediastack)"
echo "Prowlarr:    http://localhost:8022"
echo "Radarr:      http://localhost:8023"
echo "Sonarr:      http://localhost:8024"
echo ""
echo "API Keys saved to: $KEYS_FILE"
echo ""
echo "REMAINING MANUAL STEPS:"
echo "1. Jellyfin  - Create admin account (first visit)"
echo "2. Jellyfin  - Add libraries: Movies=/media/movies, Shows=/media/shows"
echo "3. Jellyseerr - Sign in with Jellyfin, then Settings > Services > Add Radarr/Sonarr"
echo "   Radarr:  http://radarr:7878  API: $RADARR_KEY"
echo "   Sonarr:  http://sonarr:8989  API: $SONARR_KEY"
echo ""
echo "Indexers (YTS, EZTV, LimeTorrents, ThePirateBay) added automatically."
