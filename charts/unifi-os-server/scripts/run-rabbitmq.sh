#!/bin/bash
# RabbitMQ for the unifi (java) app: TLS on *:5671.
# Runs on the official rabbitmq image; the cert contract with java is
# unchanged (root.cert + client.cert/client.key in /etc/rabbitmq/ssl, which
# run-unifi.sh turns into PKCS12 keystores).
set -e

SSL=/etc/rabbitmq/ssl
if [ -z "$(ls -A $SSL 2>/dev/null)" ]; then
  umask 077
  cd $SSL
  openssl req -x509 -newkey rsa:2048 -nodes -keyout root.key -out root.cert \
    -days 3650 -subj "/CN=UniFi-OS-CA"
  openssl req -newkey rsa:2048 -nodes -keyout server.key -out /tmp/s.csr \
    -subj "/CN=rabbitmq"
  openssl x509 -req -in /tmp/s.csr -CA root.cert -CAkey root.key -CAcreateserial \
    -out server.cert -days 3650
  openssl req -newkey rsa:2048 -nodes -keyout client.key -out /tmp/c.csr \
    -subj "/CN=unifi"
  openssl x509 -req -in /tmp/c.csr -CA root.cert -CAkey root.key -CAcreateserial \
    -out client.cert -days 3650
  rm -f /tmp/s.csr /tmp/c.csr root.srl
  chown -R rabbitmq:ssl-cert $SSL 2>/dev/null || true
  chmod -R a+rX $SSL
fi

# TLS listener on 5671, server cert signed by the local CA, and a client
# certificate is mandatory (the java app presents client.cert/key).
cat > /etc/rabbitmq/rabbitmq.conf <<EOF
listeners.tcp.default = 5672
listeners.ssl.default = 5671
ssl_options.cacertfile = /etc/rabbitmq/ssl/root.cert
ssl_options.certfile = /etc/rabbitmq/ssl/server.cert
ssl_options.keyfile = /etc/rabbitmq/ssl/server.key
ssl_options.verify = verify_peer
ssl_options.fail_if_no_peer_cert = true
EOF

# official image: rabbitmq is uid 999; volume may be owned by the UOS image's
# uid 130. Normalize so the existing mnesia data + .erlang.cookie carry over.
chown -R rabbitmq:rabbitmq /var/lib/rabbitmq

exec runuser -u rabbitmq -- env HOME=/var/lib/rabbitmq rabbitmq-server
