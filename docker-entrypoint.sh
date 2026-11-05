#!/bin/sh
# Applies pending PostgreSQL migrations, then starts the standalone Next.js server.
set -e
echo "Applying database migrations..."
node node_modules/prisma/build/index.js migrate deploy --schema prisma/schema.postgres.prisma
echo "Starting EcomOS on port ${PORT:-3000}"
exec node server.js
