{
  description = "Declarative Jellyfin media stack";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    declarative-jellyfin.url = "github:Sveske-Juice/declarative-jellyfin";
  };

  outputs = { nixpkgs, declarative-jellyfin, ... }: {
    nixosModules.default = { config, pkgs, lib, ... }: {
      imports = [ declarative-jellyfin.nixosModules.default ];

      # Jellyfin - declarative config
      services.declarative-jellyfin = {
        enable = true;

        system = {
          serverName = "Media Server";
        };

        users = {
          admin = {
            mutable = false;
            permissions.isAdministrator = true;
            # Generate with: nix run github:Sveske-Juice/declarative-jellyfin#genhash -- -i 210000 -l 128 -u -k "yourpassword"
            # hashedPasswordFile = /path/to/hashed-password;
          };
        };

        libraries = {
          Movies = {
            contentType = "movies";
            paths = [ "/media/movies" ];
          };
          Shows = {
            contentType = "tvshows";
            paths = [ "/media/shows" ];
          };
        };
      };

      # Sonarr
      services.sonarr = {
        enable = true;
        openFirewall = true;
      };

      # Radarr
      services.radarr = {
        enable = true;
        openFirewall = true;
      };

      # Prowlarr
      services.prowlarr = {
        enable = true;
        openFirewall = true;
      };

      # Jellyseerr
      services.jellyseerr = {
        enable = true;
        openFirewall = true;
      };

      # Transmission
      services.transmission = {
        enable = true;
        openFirewall = true;
        settings = {
          download-dir = "/var/lib/transmission/downloads";
          incomplete-dir = "/var/lib/transmission/incomplete";
          rpc-bind-address = "0.0.0.0";
          rpc-whitelist-enabled = false;
        };
      };

      # Create media directories
      systemd.tmpfiles.rules = [
        "d /media/movies 0775 jellyfin jellyfin -"
        "d /media/shows 0775 jellyfin jellyfin -"
      ];

      # Configure Prowlarr indexers via API after startup
      systemd.services.prowlarr-indexers = {
        description = "Configure Prowlarr indexers";
        after = [ "prowlarr.service" ];
        wants = [ "prowlarr.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.curl pkgs.jq ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # Wait for Prowlarr to be ready
          for i in $(seq 1 30); do
            if curl -s http://localhost:9696/api/v1/health > /dev/null 2>&1; then
              break
            fi
            sleep 2
          done

          # Get API key from Prowlarr config
          API_KEY=$(grep -oP '(?<=<ApiKey>)[^<]+' /var/lib/prowlarr/config.xml 2>/dev/null || echo "")
          if [ -z "$API_KEY" ]; then
            echo "Could not get Prowlarr API key, skipping indexer setup"
            exit 0
          fi

          # Get existing indexers
          EXISTING=$(curl -s "http://localhost:9696/api/v1/indexer" -H "X-Api-Key: $API_KEY" | jq -r '.[].fields[] | select(.name == "definitionFile") | .value')

          # Movies, TV, and Anime indexers (verified working)
          INDEXERS="
            yts
            eztv
            limetorrents
            thepiratebay
            torrentdownloads
            bitsearch
            moviesdvdr
            nyaasi
            tokyotosho
            mikan
            acgrip
            dmhy
            shanaproject
            elitetorrent-wf
            rutor
            bigfangroup
          "

          # Add indexers if not already present
          for indexer in $INDEXERS; do
            if echo "$EXISTING" | grep -q "^$indexer$"; then
              echo "Indexer $indexer already exists, skipping"
              continue
            fi
            echo "Adding indexer: $indexer"
            curl -s -X POST "http://localhost:9696/api/v1/indexer" \
              -H "X-Api-Key: $API_KEY" \
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

          echo "Indexers configured"
        '';
      };
    };
  };
}
