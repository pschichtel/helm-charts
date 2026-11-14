#!/bin/bash
# unifi-core: the UniFi OS core service (Node.js), foreground.
# Owns the shared network namespace of the whole app tier.
set -e

# --- static metadata the app expects (normally provided by the firmware)
echo linux-x64 > /usr/lib/platform
echo "UniFi OS Server" > /usr/lib/product_name
echo UOSSERVER > /usr/lib/app_model
echo "UOSSERVER.0000000.5.1.42.000000.0000.0000" > /usr/lib/version
echo "${UOS_UUID:?set UOS_UUID in .env}" > /data/uos_uuid

# --- wait for postgres (roles/DBs are pre-created by the postgres service)
for i in $(seq 1 60); do pg_isready -q -h postgres -p 5432 && break; sleep 2; done

mkdir -p /data/unifi-core/config/http /run/unifi-core

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

# --- point core at the shared postgres service (node-config deployment override)
mkdir -p /data/unifi-core/config/overrides
cat > /data/unifi-core/config/overrides/production.yaml <<EOF
postgres:
  host: postgres
EOF

# --- ownership (pre-start chowns the rest)
chown -R unifi-core:unifi-core /data/unifi-core
chown unifi-core:unifi-core /run/unifi-core; chmod 755 /run/unifi-core

# --- D-Bus system bus + fake systemd1 provider (root)
mkdir -p /var/run/dbus
rm -f /var/run/dbus/system_bus_socket /var/run/dbus/pid
dbus-daemon --system --fork
/usr/bin/node24 /opt/fake-sd1.js >/tmp/fakesd.log 2>&1 &
for i in $(seq 1 30); do grep -q FAKE-SD1-READY /tmp/fakesd.log 2>/dev/null && break; sleep 1; done

# --- crash catcher so uncaught errors are visible in the log
cat > /tmp/pre.js <<'EOF'
process.on('uncaughtException', function(e){ try { process.stderr.write('REAL-UNCAUGHT ' + (e && e.stack ? e.stack : String(e)) + '\n'); } catch(_){} });
process.on('unhandledRejection', function(e){ try { process.stderr.write('REAL-REJECT ' + (e && e.stack ? e.stack : String(e)) + '\n'); } catch(_){} });
process.on('exit', function(c){ try { process.stderr.write('NODE-EXIT code=' + c + '\n'); } catch(_){} });
EOF
chmod 644 /tmp/pre.js

# --- pre-start hook (validated: as unifi-core, cwd /tmp)
runuser -u unifi-core -- env TMPDIR=/tmp bash -c 'cd /tmp && /usr/share/unifi-core/app/hooks/pre-start' || true

# --- nginx: full config from the image, then start it (retry: core generates
# the site confs + certs in /data/unifi-core/config/http on boot, so the first
# nginx -t may fail). Core reloads it at runtime via `nginx -s reload`.
cp /etc/nginx/nginx.conf.disabled /etc/nginx/nginx.conf
( for i in $(seq 1 60); do nginx -t >/dev/null 2>&1 && nginx && break; sleep 5; done ) &

# --- foreground: the core service itself
cd /usr/share/unifi-core/app
exec runuser -u unifi-core -- env \
  NODE_ENV=production UV_THREADPOOL_SIZE=256 \
  NODE_CONFIG_DIR="/usr/share/unifi-core/app/config/:/data/unifi-core/config/overrides/" \
  /usr/bin/node24 --require /tmp/pre.js --expose-gc --max-old-space-size=300 --openssl-legacy-provider \
  --no-network-family-autoselection --dns-result-order=ipv4first \
  /usr/share/unifi-core/app/service.js
