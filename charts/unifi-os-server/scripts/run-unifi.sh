#!/bin/bash
# unifi: the Java "ace" application, foreground.
set -e

# --- loopback bridges to the other services (see netbridge.sh)
/scripts/netbridge.sh

# --- wait for core's IPC API (tolerates core being briefly down). Must be an
# HTTP check: 127.0.0.1:11081 is answered by the local netbridge forwarder
# immediately, so a plain TCP check would pass before core is actually up.
for i in $(seq 1 90); do curl -sf -o /dev/null http://127.0.0.1:11081/api/info && break; sleep 2; done

# --- first-boot UOS init (root)
/usr/sbin/unifi-network-service-helper init-uos || true

# --- system.properties: external mongo, rmq by hostname, postgres by env
mkdir -p /var/lib/unifi
cat > /var/lib/unifi/system.properties <<EOF
system_ip=${UOS_SYSTEM_IP:?set UOS_SYSTEM_IP in .env}
db.mongo.local=false
db.mongo.uri=mongodb://unifi-os-server-mongodb:27017/ace?tls=false
statdb.mongo.uri=mongodb://unifi-os-server-mongodb:27017/ace_stat?tls=false
rmq.host=rabbitmq
rmq.port=5671
EOF
chown unifi:unifi /var/lib/unifi/system.properties

# --- TLS material for the RMQ handshake (from the shared rabbitmq-ssl volume):
# truststore = UOS root CA (verify server), keystore = client cert+key (server
# demands a peer cert). Rebuild when inputs change.
SSLIN=/etc/rabbitmq/ssl
SSLDIR=/var/lib/unifi/ssl
mkdir -p "$SSLDIR"
if [ -f "$SSLIN/root.cert" ] && [ -f "$SSLIN/client.cert" ] && [ -f "$SSLIN/client.key" ]; then
  if [ ! -f "$SSLDIR/truststore.p12" ] || [ "$SSLIN/root.cert" -nt "$SSLDIR/truststore.p12" ]; then
    rm -f "$SSLDIR/truststore.p12"
    keytool -import -alias uos-root -file "$SSLIN/root.cert" -storetype PKCS12 \
      -storepass changeit -keystore "$SSLDIR/truststore.p12" -noprompt 2>/dev/null
  fi
  if [ ! -f "$SSLDIR/keystore.p12" ] || [ "$SSLIN/client.cert" -nt "$SSLDIR/keystore.p12" ] || [ "$SSLIN/client.key" -nt "$SSLDIR/keystore.p12" ]; then
    rm -f "$SSLDIR/keystore.p12"
    openssl pkcs12 -export -in "$SSLIN/client.cert" -inkey "$SSLIN/client.key" \
      -out /tmp/client.p12 -passout pass:changeit 2>/dev/null
    keytool -importkeystore -srckeystore /tmp/client.p12 -srcstoretype PKCS12 \
      -srcstorepass changeit -destkeystore "$SSLDIR/keystore.p12" \
      -deststoretype PKCS12 -deststorepass changeit -noprompt 2>/dev/null
    rm -f /tmp/client.p12
  fi
fi
chown -R unifi:unifi /var/lib/unifi 2>/dev/null || true

# --- first-run helper dirs (normally created by the entrypoint/systemd)
mkdir -p /data/unifi/logs /data/unifi/run /run/unifi
chown -R unifi:unifi /var/lib/unifi /data/unifi /run/unifi 2>/dev/null || true

# --- foreground: the java app (user unifi, cwd /usr/lib/unifi/)
cd /usr/lib/unifi
exec runuser -u unifi -- env logDir=/data/unifi/logs \
  UNIFI_POSTGRESQL_HOST=postgres UNIFI_POSTGRESQL_PORT=5432 \
  /usr/bin/java -Dfile.encoding=UTF-8 -Djava.awt.headless=true -Dapple.awt.UIElement=true \
  -XX:+UseG1GC -XX:MaxRAMPercentage=70.0 -Xss1024K -XX:-TieredCompilation \
  -XX:+ExitOnOutOfMemoryError -XX:+CrashOnOutOfMemoryError -Xmx512M \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  --add-opens java.base/java.time=ALL-UNNAMED \
  --add-opens java.base/sun.security.util=ALL-UNNAMED \
  --add-opens java.base/java.io=ALL-UNNAMED \
  --add-opens java.rmi/sun.rmi.transport=ALL-UNNAMED \
  -Dspring.profiles.active=unifi-os \
  -Dunifi.core.enabled=true \
  -Dunifi.mongodb.service.enabled=false \
  -Dunifi.rmq.enabled=true \
  -Dunifi.rmq.certificates=/etc/rabbitmq/ssl \
  -Dspring.rabbitmq.host=rabbitmq \
  -Dspring.rabbitmq.port=5671 \
  -Dspring.rabbitmq.ssl.enabled=true \
  -Dspring.rabbitmq.ssl.verify-hostname=false \
  -Dspring.rabbitmq.ssl.key-store=file:/var/lib/unifi/ssl/keystore.p12 \
  -Dspring.rabbitmq.ssl.key-store-password=changeit \
  -Dspring.rabbitmq.ssl.key-store-type=PKCS12 \
  -Dspring.rabbitmq.ssl.trust-store=file:/var/lib/unifi/ssl/truststore.p12 \
  -Dspring.rabbitmq.ssl.trust-store-password=changeit \
  -Dspring.rabbitmq.ssl.trust-store-type=PKCS12 \
  -Dunifi-os.server=true \
  -Dorg.xerial.snappy.tempdir=/usr/lib/unifi/run \
  -Dunifi.external_disk.inserted= \
  -jar /usr/lib/unifi/lib/ace.jar
