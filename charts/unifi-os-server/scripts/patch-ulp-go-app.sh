#!/usr/bin/env bash
# Patch the xorm-fork GetColumns SQL template bug in /usr/sbin/ulp-go-app.
#
# Root cause: the vendored xorm fork's postgres dialect builds the GetColumns
# query from a Go template ending in:  ... c.relname = $1%s AND f.attnum > 0
# The code substitutes the literal "AND s.table_schema = $2" (no leading
# space) into %s, producing invalid SQL:
#   ... c.relname = $1AND s.table_schema = $2 AND f.attnum > 0 ...
# which Postgres rejects with: "trailing junk after parameter at or near $1AND".
# Any Sync2() call on an EXISTING table hits this query and panics at boot.
#
# Fix: zero-length rewrite of the template string inside the binary:
#   "n.nspname= s.table_schema" -> "n.nspname=s.table_schema"  (drop one space)
#   "$1%s"                      -> "$1 %s"                    (add one space)
# Resulting runtime SQL is valid:
#   ... WHERE n.nspname=s.table_schema AND c.relkind = 'r'::char
#       AND c.relname = $1 AND s.table_schema = $2 AND f.attnum > 0 ...
# Same byte length, so no Go string-length metadata is invalidated.
# Idempotent: safe to run every boot; no-ops once patched.
set -euo pipefail

BIN="${1:-/usr/sbin/ulp-go-app}"

perl -e '
  local $/;
  open(my $F, "<:raw", $ARGV[0]) or die "open: $!";
  my $d = <$F>;
  close $F;
  my $old = "WHERE n.nspname= s.table_schema AND c.relkind = \x27r\x27::char AND c.relname = \$1%s AND f.attnum > 0 ORDER BY f.attnum;";
  my $new = "WHERE n.nspname=s.table_schema AND c.relkind = \x27r\x27::char AND c.relname = \$1 %s AND f.attnum > 0 ORDER BY f.attnum;";
  my $n = index($d, $old);
  if ($n < 0) {
    # Already patched (or template changed) - verify new form is present.
    if (index($d, $new) >= 0) { print "ulp-go-app: already patched\n"; exit 0; }
    die "ulp-go-app: template not found and no patch present - refusing to continue\n";
  }
  # Count occurrences (must be exactly one).
  my $cnt = 0; my $i = -1;
  while ((my $j = index($d, $old, $i + 1)) >= 0) { $cnt++; $i = $j; }
  die "ulp-go-app: expected 1 template occurrence, found $cnt\n" if $cnt != 1;
  substr($d, $n, length($old)) = $new;
  open(my $O, ">:raw", $ARGV[0]) or die "write: $!";
  print $O $d;
  close $O;
  print "ulp-go-app: GetColumns template patched\n";
' "$BIN"
