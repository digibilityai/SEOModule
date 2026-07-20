#!/bin/sh

cat <<EOF > /usr/share/nginx/html/runtime-config.js
window.RUNTIME_CONFIG = {
  SUPABASE_URL: "${SUPABASE_URL}",
  SUPABASE_ANON_KEY: "${SUPABASE_ANON_KEY}",
  SEO_DATA_MODE: "${SEO_DATA_MODE:-supabase}",
  DIGIBILITY_APP_URL: "${DIGIBILITY_APP_URL}",
  DIGIBILITY_BRIDGE_URL: "${DIGIBILITY_BRIDGE_URL}",
  DIGIBILITY_ANON_KEY: "${DIGIBILITY_ANON_KEY}"
};
EOF

nginx -g "daemon off;"
