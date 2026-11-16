#!/bin/bash
# unifi-core: the UniFi OS core service (Node.js), foreground.
set -e
source /scripts/lib.sh

# Console identity (/usr/lib/{platform,product_name,app_model,version}) is
# mounted from the chart's ConfigMap; the device UUID comes from the env.
echo "${UOS_UUID:?UOS_UUID is not set}" > /data/uos_uuid

# --- wait for postgres (database and user are provided externally)
wait_for_postgres

# logs/ must exist before nginx starts: nginx.conf writes nginx-access.log there
mkdir -p /data/unifi-core/config/http /data/unifi-core/logs /run/unifi-core

# --- idempotent service.js patches: 8s boot delay for the two top-level
# IIFEs that race the (fake) systemd provider
python3 - <<'EOF'
p='/usr/share/unifi-core/app/service.js'
s=open(p).read()
delay='await new Promise(r=>setTimeout(r,8000));'
n=0
a1='(async()=>{let{timezone:J,name:se,anonymous_device_id:be,lcmSettings:$e,ledSettings:re,isSetup:je}=Te();'
if a1 in s:
    s=s.replace(a1,'(async()=>{'+delay+'let{timezone:J,name:se,anonymous_device_id:be,lcmSettings:$e,ledSettings:re,isSetup:je}=Te();',1)
    n+=1
a2='(async()=>{try{if(!await gn.pathExists(qM))return;'
i=s.find(a2)
if i>=0:
    s=s[:i]+'(async()=>{'+delay+s[i+len('(async()=>{'):]
    n+=1
open(p,'w').write(s)
print('service.js IIFE delays applied:',n)
EOF

# --- idempotent handoff patch: publish with no subscribers must not be fatal
python3 - <<'EOF'
p='/usr/share/unifi-core/app/node_modules/handoff/handoff.js'
s=open(p).read()
old="""  let err = new Error(n.name + ' was published but has no subscribers.')
  err.code = 'ENOSYS'

  n.cancel()

  return Promise.reject(err)"""
new="""  n.cancel()

  console.error('[handoff] no subscribers for "' + n.name + '" - dropping notification')
  return Promise.resolve()"""
if s.count(old)==1:
    open(p,'w').write(s.replace(old,new))
    print('handoff patched')
else:
    print('handoff already patched (anchor count=%d)' % s.count(old))
EOF

# --- idempotent service.js patch: guard the firmware-update semver comparison.
# The current-version string ("...5.1...") is not valid semver, and the check
# fires as soon as ulp-go publishes its ulp events; a throw here is fatal.
python3 - <<'EOF'
p='/usr/share/unifi-core/app/service.js'
s=open(p).read()
old='var EYe=()=>{let e=xc(),{firmwareVersion:t}=G();return LE.gt(e,t)?DD():null},ji=EYe;'
new='var EYe=()=>{try{let e=xc(),{firmwareVersion:t}=G();return LE.gt(e,t)?DD():null}catch(_x){return null}},ji=EYe;'
if s.count(old)==1:
    open(p,'w').write(s.replace(old,new))
    print('EYe guard applied')
elif new in s:
    print('EYe guard present')
else:
    print('EYe anchor missing (count=%d)' % s.count(old))
EOF

# --- point core at the external postgres (node-config deployment override).
# Written as JSON (valid YAML) so any password survives unescaped. pg_dump /
# pg_restore (backups) read PGHOST/PGPORT/PGUSER/PGPASSWORD from the env.
mkdir -p /data/unifi-core/config/overrides
python3 - <<'EOF'
import json, os
cfg = {"postgres": {
    "host": os.environ["PGHOST"],
    "port": int(os.environ.get("PGPORT", "5432")),
    "user": os.environ["PGUSER"],
    "password": os.environ["PGPASSWORD"],
    "database": os.environ.get("DB_NAME", "unifi-core"),
}}
path = "/data/unifi-core/config/overrides/production.yaml"
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(cfg, f, indent=2)
EOF

# --- ownership (pre-start chowns the rest)
chown -R unifi-core:unifi-core /data/unifi-core
chown unifi-core:unifi-core /run/unifi-core; chmod 755 /run/unifi-core

# --- D-Bus system bus + fake systemd1 provider (root)
mkdir -p /var/run/dbus
rm -f /var/run/dbus/system_bus_socket /var/run/dbus/pid
dbus-daemon --system --fork
/usr/bin/node24 /scripts/fake-sd1.js >/tmp/fakesd.log 2>&1 &
for _ in $(seq 1 30); do grep -q FAKE-SD1-READY /tmp/fakesd.log 2>/dev/null && break; sleep 1; done

# --- crash catcher so uncaught errors are visible in the log
cat > /tmp/pre.js <<'EOF'
process.on('uncaughtException', function(e){ try { process.stderr.write('REAL-UNCAUGHT ' + (e && e.stack ? e.stack : String(e)) + '\n'); } catch(_){} });
process.on('unhandledRejection', function(e){ try { process.stderr.write('REAL-REJECT ' + (e && e.stack ? e.stack : String(e)) + '\n'); } catch(_){} });
process.on('exit', function(c){ try { process.stderr.write('NODE-EXIT code=' + c + '\n'); } catch(_){} });
EOF
chmod 644 /tmp/pre.js

# --- pre-start hook (validated: as unifi-core, cwd /tmp)
runuser -u unifi-core -- env TMPDIR=/tmp bash -c 'cd /tmp && /usr/share/unifi-core/app/hooks/pre-start' || true

# --- nginx: full config from the image. It must be RUNNING before core starts:
# core writes its site confs and immediately runs `nginx -s reload`; if that
# fails, core treats the unhandled rejection as fatal and exits (the container
# then restarts once). The config is valid without core's files (all includes
# are wildcards), so start it now. The retry loop is only a fallback.
cp /etc/nginx/nginx.conf.disabled /etc/nginx/nginx.conf
if nginx -t >/dev/null 2>&1 && nginx; then
  :
else
  echo "nginx did not start before core; retrying in the background" >&2
  nginx -t >&2 || true
  ( for _ in $(seq 1 60); do sleep 5; nginx -t >/dev/null 2>&1 && nginx && break; done ) &
fi

# --- foreground: the core service itself
cd /usr/share/unifi-core/app
exec runuser -u unifi-core -- env \
  NODE_ENV=production UV_THREADPOOL_SIZE="${UV_THREADPOOL_SIZE:-256}" \
  NODE_CONFIG_DIR="/usr/share/unifi-core/app/config/:/data/unifi-core/config/overrides/" \
  /usr/bin/node24 --require /tmp/pre.js --expose-gc --max-old-space-size=300 --openssl-legacy-provider \
  --no-network-family-autoselection --dns-result-order=ipv4first \
  /usr/share/unifi-core/app/service.js
