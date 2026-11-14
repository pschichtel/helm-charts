#!/bin/bash
# This stack uses trust auth (no passwords) for all components.
{
  echo "local all all trust"
  echo "host all all all trust"
} > "$PGDATA/pg_hba.conf"
