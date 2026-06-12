# Custom spawn hub schematic

Drop a WorldEdit `.schem` file here as:

  server/assets/pisces-spawn.schem

Recommended size: 150x150 to 250x250 (flat hub on void or flat world).

Then on the VPS:

  sudo SKIP_UFW=1 bash /opt/piscessmp/scripts/setup-spawn.sh

Or set a direct download URL:

  sudo SCHEM_URL='https://example.com/MyHub.schem' SKIP_UFW=1 bash /opt/piscessmp/scripts/setup-spawn.sh

License: only use schematics you have rights to (CC / purchased / your own build).
