#!/bin/bash
# unifi: the Java "ace" application (UniFi Network), foreground.
#
# Uses MongoDB (db.mongo.uri / statdb.mongo.uri) and RabbitMQ (rmq.*). It
# does not use Postgres: its Postgres code is only active with
# unifi.active.db.mode=postgresql|combined, the default is mongo.
set -e

# --- wait for core's IPC API (tolerates core being briefly down)
for _ in $(seq 1 90); do curl -sf -o /dev/null http://127.0.0.1:11081/api/info && break; sleep 2; done

# --- first-boot UOS init (root)
/usr/sbin/unifi-network-service-helper init-uos || true

# --- system.properties from the environment. Written with python so that
# credentials are URL-encoded in the Mongo URIs and escaped for the Java
# properties format.
mkdir -p /var/lib/unifi
python3 - <<'EOF'
import os, urllib.parse as up

def env(name, default=None, required=False):
    v = os.environ.get(name, default)
    if required and not v:
        raise SystemExit(f"{name} is not set")
    return v

def mongo_uri(db):
    user = up.quote(env("MONGO_USERNAME", required=True), safe="")
    pw = up.quote(env("MONGO_PASSWORD", required=True), safe="")
    hosts = env("MONGO_HOSTS", required=True)
    q = {"authSource": env("MONGO_AUTH_SOURCE", "admin")}
    if env("MONGO_REPLICA_SET"):
        q["replicaSet"] = env("MONGO_REPLICA_SET")
    q["tls"] = "true" if env("MONGO_TLS", "false") == "true" else "false"
    uri = f"mongodb://{user}:{pw}@{hosts}/{db}?{up.urlencode(q)}"
    extra = env("MONGO_EXTRA_OPTIONS", "")
    return uri + ("&" + extra if extra else "")

def prop(v):
    # java.util.Properties: escape backslashes; leading spaces would be eaten
    return v.replace("\\", "\\\\").replace("\n", "\\n")

props = {}
if env("UOS_SYSTEM_IP"):
    props["system_ip"] = env("UOS_SYSTEM_IP")
props.update({
    "db.mongo.local": "false",
    "db.mongo.uri": mongo_uri(env("MONGO_DATABASE", "ace")),
    "statdb.mongo.uri": mongo_uri(env("MONGO_STAT_DATABASE", "ace_stat")),
    "rmq.host": env("RABBITMQ_HOST", required=True),
    "rmq.port": env("RABBITMQ_PORT", "5672"),
    "rmq.username": env("RABBITMQ_USERNAME", required=True),
    "rmq.password": env("RABBITMQ_PASSWORD", required=True),
})
path = "/var/lib/unifi/system.properties"
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    for k, v in props.items():
        f.write(f"{k}={prop(v)}\n")
EOF

# --- optional TLS to RabbitMQ: trust store from the CA in RABBITMQ_TLS_CA_FILE
RMQ_TLS_FLAGS=()
if [ "${RABBITMQ_TLS:-false}" = true ]; then
  SSLDIR=/var/lib/unifi/ssl
  mkdir -p "$SSLDIR"
  rm -f "$SSLDIR/rabbitmq-truststore.p12"
  keytool -import -alias rabbitmq-ca -file "${RABBITMQ_TLS_CA_FILE:?RABBITMQ_TLS_CA_FILE is not set}" \
    -storetype PKCS12 -storepass changeit -keystore "$SSLDIR/rabbitmq-truststore.p12" -noprompt >/dev/null
  RMQ_TLS_FLAGS=(
    -Dspring.rabbitmq.ssl.enabled=true
    -Dspring.rabbitmq.ssl.verify-hostname="${RABBITMQ_TLS_VERIFY_HOSTNAME:-true}"
    "-Dspring.rabbitmq.ssl.trust-store=file:$SSLDIR/rabbitmq-truststore.p12"
    -Dspring.rabbitmq.ssl.trust-store-password=changeit
    -Dspring.rabbitmq.ssl.trust-store-type=PKCS12
  )
fi

# --- Spring Boot's RabbitMQ settings. The app's ConnectionFactoryCustomizer
# applies rmq.* from system.properties, but the broker address only took
# effect through Spring's own properties in testing. Passed as environment
# variables (relaxed binding) so the password is not on the command line.
export SPRING_RABBITMQ_HOST="$RABBITMQ_HOST" SPRING_RABBITMQ_PORT="${RABBITMQ_PORT:-5672}" \
  SPRING_RABBITMQ_USERNAME="$RABBITMQ_USERNAME" SPRING_RABBITMQ_PASSWORD="$RABBITMQ_PASSWORD"

# --- first-run helper dirs (normally created by the entrypoint/systemd)
mkdir -p /data/unifi/logs /data/unifi/run /run/unifi
chown -R unifi:unifi /var/lib/unifi /data/unifi /run/unifi

# --- foreground: the java app (user unifi, cwd /usr/lib/unifi/)
cd /usr/lib/unifi
exec runuser -u unifi -- env logDir=/data/unifi/logs \
  /usr/bin/java -Dfile.encoding=UTF-8 -Djava.awt.headless=true -Dapple.awt.UIElement=true \
  -XX:+UseG1GC -XX:MaxRAMPercentage=70.0 -Xss1024K -XX:-TieredCompilation \
  -XX:+ExitOnOutOfMemoryError -XX:+CrashOnOutOfMemoryError -Xmx"${JAVA_MAX_HEAP:-512M}" \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  --add-opens java.base/java.time=ALL-UNNAMED \
  --add-opens java.base/sun.security.util=ALL-UNNAMED \
  --add-opens java.base/java.io=ALL-UNNAMED \
  --add-opens java.rmi/sun.rmi.transport=ALL-UNNAMED \
  -Dspring.profiles.active=unifi-os \
  -Dunifi.core.enabled=true \
  -Dunifi.mongodb.service.enabled=false \
  -Dunifi.rmq.enabled=true \
  "${RMQ_TLS_FLAGS[@]}" \
  -Dunifi-os.server=true \
  -Dorg.xerial.snappy.tempdir=/usr/lib/unifi/run \
  -Dunifi.external_disk.inserted= \
  -jar /usr/lib/unifi/lib/ace.jar
