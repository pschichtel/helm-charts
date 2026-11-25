#!/bin/bash
# Entrypoint of the unifi-os-server container. Runs the image's systemd like
# the upstream entrypoint (/root/uos-entrypoint.sh), with PostgreSQL, MongoDB
# and RabbitMQ outside the container. Everything else is the stock image; see
# the chart README ("How the container is set up").
set -euo pipefail

# Journal replay boundary for the log forwarder (the host's boot ID is shared).
SINCE="@$(date +%s)"
log() { echo "boot: $*"; }

# --- console identity (as the upstream entrypoint)
echo "$UOS_UUID" > /data/uos_uuid
echo "$UOS_PLATFORM" > /usr/lib/platform
echo "$UOS_PRODUCT_NAME" > /usr/lib/product_name
echo "$UOS_APP_MODEL" > /usr/lib/app_model
echo "$UOS_VERSION" > /usr/lib/version

# --- the local data services are replaced by the external ones. Not useful
# in a privileged container: kernel parameters (systemd-sysctl), and logins on
# the node's consoles, which also make systemd wait 90 s for their devices.
for u in rabbitmq-server.service epmd.service epmd.socket systemd-sysctl.service \
  postgresql@14-main.service postgresql-cluster@14-main.service \
  getty@.service serial-getty@.service; do
  ln -sfn /dev/null "/etc/systemd/system/$u"
done
# the node's kernel log is visible here; keep it out of the journal
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nReadKMsg=no\n' > /etc/systemd/journald.conf.d/50-chart.conf
# Network 10.6+ runs "systemctl start mongodb" (or mongod, unifi-mongodb) at
# startup and refuses to start if all fail; a no-op unit lets it continue
# with the external server from system.properties.
cat > /etc/systemd/system/mongodb.service <<EOF
[Unit]
Description=MongoDB (external server, nothing runs here)
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
EOF

# --- PostgreSQL: the apps connect to the local socket (and 127.0.0.1:5432) as
# password-less roles and create their roles and databases as "postgres". A
# systemd socket proxy forwards both to the external server, which therefore
# has to trust the pod.
cat > /etc/systemd/system/uos-postgresql-proxy.socket <<EOF
[Unit]
Description=Socket of the external PostgreSQL server
[Socket]
ListenStream=/run/postgresql/.s.PGSQL.5432
ListenStream=127.0.0.1:5432
SocketMode=0777
[Install]
WantedBy=sockets.target
EOF
cat > /etc/systemd/system/uos-postgresql-proxy.service <<EOF
[Unit]
Description=Proxy to the external PostgreSQL server ${PG_HOST}:${PG_PORT}
Requires=uos-postgresql-proxy.socket
After=uos-postgresql-proxy.socket
[Service]
ExecStart=/lib/systemd/systemd-socket-proxyd ${PG_HOST}:${PG_PORT}
EOF
mkdir -p /etc/systemd/system/sockets.target.wants
ln -sfn ../uos-postgresql-proxy.socket /etc/systemd/system/sockets.target.wants/uos-postgresql-proxy.socket

# --- MongoDB and RabbitMQ for the Network app: keys in its system.properties
# (the app keeps its own state in the same file, so only these keys are
# replaced) and Spring's RabbitMQ settings in a unit drop-in.
mkdir -p /etc/uos-chart /var/lib/unifi
if [ "${RABBITMQ_TLS:-false}" = true ]; then
  rm -f /etc/uos-chart/rabbitmq-truststore.p12
  keytool -import -noprompt -alias rabbitmq-ca -file "$RABBITMQ_TLS_CA_FILE" -storetype PKCS12 \
    -storepass changeit -keystore /etc/uos-chart/rabbitmq-truststore.p12 >/dev/null
  chmod 644 /etc/uos-chart/rabbitmq-truststore.p12
fi
python3 - <<'EOF'
import os, urllib.parse as up

env = os.environ.get

def mongo_uri(db):
    q = {"authSource": env("MONGO_AUTH_SOURCE") or "admin"}
    if env("MONGO_REPLICA_SET"):
        q["replicaSet"] = env("MONGO_REPLICA_SET")
    q["tls"] = "true" if env("MONGO_TLS") == "true" else "false"
    uri = "mongodb://%s:%s@%s/%s?%s" % (
        up.quote(env("MONGO_USERNAME"), safe=""), up.quote(env("MONGO_PASSWORD"), safe=""),
        env("MONGO_HOSTS"), db, up.urlencode(q))
    return uri + ("&" + env("MONGO_EXTRA_OPTIONS") if env("MONGO_EXTRA_OPTIONS") else "")

props = {
    "db.mongo.local": "false",
    "db.mongo.uri": mongo_uri(env("MONGO_DATABASE") or "ace"),
    "statdb.mongo.uri": mongo_uri(env("MONGO_STAT_DATABASE") or "ace_stat"),
    "rmq.host": env("RABBITMQ_HOST"),
    "rmq.port": env("RABBITMQ_PORT") or "5672",
    "rmq.username": env("RABBITMQ_USERNAME"),
    "rmq.password": env("RABBITMQ_PASSWORD"),
}
if env("UOS_SYSTEM_IP"):
    props["system_ip"] = env("UOS_SYSTEM_IP")
managed = set(props) | {"system_ip"}

path = "/var/lib/unifi/system.properties"
keep = []
if os.path.exists(path):
    with open(path) as f:
        for line in f:
            key = line.split("=", 1)[0].strip()
            if "=" in line and not line.lstrip().startswith(("#", "!")) and key in managed:
                continue
            keep.append(line if line.endswith("\n") else line + "\n")
with open(path + ".chart", "w") as f:
    f.writelines(keep)
    for k, v in props.items():
        f.write("%s=%s\n" % (k, v.replace("\\", "\\\\")))
os.chmod(path + ".chart", 0o600)
os.replace(path + ".chart", path)

# Spring's RabbitMQ settings: the broker address only takes effect this way.
# An empty certificates dir turns off the stock client-certificate login to
# the local broker.
spring = {
    "UNIFI_MQ_CERTIFICATES_DIR": "",
    "SPRING_RABBITMQ_HOST": env("RABBITMQ_HOST"),
    "SPRING_RABBITMQ_PORT": env("RABBITMQ_PORT") or "5672",
    "SPRING_RABBITMQ_USERNAME": env("RABBITMQ_USERNAME"),
    "SPRING_RABBITMQ_PASSWORD": env("RABBITMQ_PASSWORD"),
}
if env("RABBITMQ_TLS") == "true":
    spring.update({
        "SPRING_RABBITMQ_SSL_ENABLED": "true",
        "SPRING_RABBITMQ_SSL_VERIFY_HOSTNAME": env("RABBITMQ_TLS_VERIFY_HOSTNAME") or "true",
        "SPRING_RABBITMQ_SSL_TRUST_STORE": "file:/etc/uos-chart/rabbitmq-truststore.p12",
        "SPRING_RABBITMQ_SSL_TRUST_STORE_PASSWORD": "changeit",
        "SPRING_RABBITMQ_SSL_TRUST_STORE_TYPE": "PKCS12",
    })
def q(v):
    return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')
fd = os.open("/etc/uos-chart/unifi.env", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    for k, v in spring.items():
        f.write("%s=%s\n" % (k, q(v)))
EOF
chown unifi:unifi /var/lib/unifi /var/lib/unifi/system.properties
mkdir -p /etc/systemd/system/unifi.service.d
cat > /etc/systemd/system/unifi.service.d/50-chart.conf <<EOF
[Service]
EnvironmentFile=/etc/uos-chart/unifi.env
EOF

# --- installed and upgraded apps (InnerSpace, newer Network versions, ...):
# dpkg caches them in /persistent/dpkg (on the volume); ubnt-dpkg-restore
# reinstalls them at boot when /boot/.fwupdate exists. The root file system
# is new on every start here, so restore every time.
mkdir -p /boot /persistent
touch /boot/.fwupdate

# --- container log: the journal (the upstream forwarder) and the apps' own log
# files (UOS_LOG_FILES, one per line), minus lines matching UOS_LOG_EXCLUDE.
# The container's stdout is kept on fd 3 because systemd replaces PID 1's.
export UOS_LOG_FORMAT="${UOS_LOG_FORMAT:-text}"
exec 3>&1
out() {
  if [ -n "${UOS_LOG_EXCLUDE:-}" ]; then
    grep --line-buffered -a -v -E -e "$UOS_LOG_EXCLUDE" >&3 || true
  else
    cat >&3
  fi
}
(
  while true; do
    /usr/bin/node24 /root/uos-logs.cjs "$SINCE" 2>&1 || true
    sleep 1
  done
) | out &

# Lines of a log file as the forwarder writes journal records: text
# "<time> [<service>] <LEVEL>: <message>" or JSON (UOS_LOG_FORMAT). The time is
# the collection time; the line keeps its own. The level is taken from the line
# (Network: "<thread> WARN", core: "- warn:"); continuation lines such as stack
# traces keep the previous one.
# shellcheck disable=SC2016
FILE_LOG_FORMATTER='
import json, os, re, sys
from datetime import datetime, timezone
path = os.environ["LOG_FILE"]
service = re.sub(r"^/data/", "", path).replace("/logs/", "/")
as_text = os.environ.get("UOS_LOG_FORMAT", "text") == "text"
level_re = re.compile(r"\b(trace|debug|info|notice|warn|warning|error|fatal|critical)\b", re.I)
names = {"trace": "debug", "warn": "warning", "fatal": "critical"}
ctrl = re.compile("[\x00-\x08\x0a-\x1f\x7f]")
level = "info"
sys.stdin.reconfigure(errors="replace")
for line in sys.stdin:
    message = line.rstrip("\r\n")
    if not message.strip():
        continue
    match = None if message[0].isspace() else level_re.search(message[:100])
    if match:
        level = names.get(match.group(1).lower(), match.group(1).lower())
    now = datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")
    if as_text:
        message = ctrl.sub(lambda c: "\\u%04x" % ord(c.group()), message)
        print("%s [%s] %s: %s" % (now, service, level.upper(), message), flush=True)
    else:
        print(json.dumps({"log_schema": "uos.v1", "source": "file", "service": service,
            "file": path, "timestamp": now, "level": level, "message": message}), flush=True)
'
while IFS= read -r f; do
  [ -n "$f" ] || continue
  (
    # -F follows rotation and waits for files that do not exist yet
    while true; do tail -F -n0 "$f" 2>/dev/null || true; sleep 1; done
  ) | LOG_FILE="$f" python3 -u -c "$FILE_LOG_FORMATTER" | out &
done <<< "${UOS_LOG_FILES:-}"

log "starting systemd"
exec /sbin/init
