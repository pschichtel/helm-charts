# Can the inter-service addresses be configured?

Short answer: **partly, and not enough to run the services in separate
network namespaces without extra plumbing.** Every component has at least one
peer address or listen address that is a literal in its code. This is why the
stack shares one network namespace between the app-tier services (see
"Networking" in the README). This document records what is configurable, what
is not, and how each claim was established, so it can be re-checked when the
image is upgraded.

"Bridge" below means a per-port TCP forwarder between containers, which is
what separate namespaces would need for every address that cannot be
configured (an earlier revision of this stack did that with `socat`).

Scope: image `ghcr.io/unihosted/unifi-os-server-docker:5.1.42`, i.e.
`unifi-core` 5.1.132, `unifi` (Network) 10.5.67, `ulp-go` 1.13.11,
`uid-agent` 1.62.1, `ucs-agent` 1.8.4, `unifi-directory` 2.7.4,
`unifi-identity-update` 1.1.12, `uos-agent` 5.1.10,
`uos-discovery-client` 5.1.1.

## Verdict per component

"Peers" is about where a service connects to; "Listen" is about which address
its own loopback-only server binds.

| Component | Peers configurable? | Listen address configurable? |
|---|---|---|
| `unifi-core` (Node) | Partly: `services.<name>.host` / `controllers.<name>.host` exist but are honoured by only 5 call sites; about 25 others are literal `127.0.0.1`. One `host` per service entry, and the `users` entry bundles ports of three different processes. Everything towards `uos-agent` is literal. Discovery client URL and Postgres host are configurable. | No. IPC `11081` and gRPC `11051` bind `127.0.0.1` in code. |
| `ulp-go` | Partly: `ucore.api` covers most calls to core. Clients for `ucs-agent`, `uid-agent`, `unifi-directory`, `unifi-identity-update` and Network are literals. | Yes: `http.listen`. |
| `ucs-agent` | Partly: `ucore.api` (undocumented) for the ws-relay, `proxy.services` for reverse-proxy targets. Message box and package installer calls to core are literals. | Yes: `http.listen`. |
| `unifi-identity-update` | No. Every client address is a literal. | Only via `http.debug = true` (switches `127.0.0.1:<port>` to `:<port>`; no other use of the key). |
| `uid-agent` | No. Core, `ulp-go` and Network clients are literals. | Not usable: `http.debug = true` would do it but the same key also relaxes `AssertFromUniFiCore` and the setup endpoints. |
| `unifi-directory` | Core yes (`ucore.api`, undocumented), Network no. | No. `127.0.0.1:%d` in code. |
| `unifi` (Java) | No. Core, `ulp-go` and `uos-agent` base URLs are constants. | No. `connector.setProperty("address", "127.0.0.1")`; only the port (`unifi.local.http.port`). |
| `uos-agent` (Rust) | n/a for this stack | No. `127.0.0.1` is an immediate operand for both listeners. |
| `uos-discovery-client` (Rust) | n/a | Yes: env `DISCOVERY_CLIENT_SERVER_HOST`. |

Consequence: `unifi-core`, `uid-agent`, `unifi-identity-update`,
`unifi-directory`, `unifi` and `uos-agent` each need a bridge in at least one
direction regardless of configuration, if they were to run in separate
namespaces.

## Method

1. **unifi-core** is a single bundled JavaScript file
   (`/usr/share/unifi-core/app/service.js`, 1.3 MB). Beautified with
   `js-beautify` and read as source. All 44 occurrences of `127.0.0.1` were
   classified.
2. **Go binaries** are stripped but keep function names in `.gopclntab`.
   A small Go program (`debug/gosym`) dumped every function's address range,
   and a Python script indexed every `LEA reg,[rip+disp]` and every
   pointer/length pair in the data sections. That gives, for any string
   literal, the functions that load it, and for any function, the strings and
   calls in it. Selected functions were then read in `objdump` disassembly.
   - Pitfall: `ulp-go` and `uid-agent` are cgo binaries. Their Go text starts
     0x100 after the `.text` section start, and `debug/gosym` assumes the
     section start. The real value is the `textStart` field of the pclntab
     header (offset 24). Without that correction every function name near a
     boundary is wrong.
   - Pitfall: Go string literals are not NUL-terminated and are packed back to
     back, so `strings` output is misleading. Lengths come from the
     `MOV reg,imm` after the `LEA`, or from the next known literal's start.
3. **Java**: `ace.jar` is a Spring Boot jar; the application classes are in
   `BOOT-INF/lib/internal-dependencies.jar` (obfuscated names). Classes
   containing loopback literals were decompiled with `jadx`.
4. **Rust**: no symbols. Environment variable names and listen messages were
   located in the binary; for `uos-agent` the code printing
   `Internal HTTP API:` / `External HTTP API:` was found through its format
   template and disassembled.
5. **Live tests** on the running stack for three of the positive findings
   (below). Changes were reverted afterwards.

Tools used: `js-beautify`, Go toolchain, `objdump`, `readelf`, `radare2`,
`jadx`. The helper scripts are not in this repository.

## Evidence

### unifi-core

- Config object: `E = require('config').util.toObject()`; service lookup is
  `Ut = e => E.services[e] || E.controllers[e]`. The stack already overrides
  this config through `/data/unifi-core/config/overrides/production.yaml`
  (used for `postgres.host`).
- `host` is read with default `127.0.0.1` by: the nginx upstream generator
  (`server ${host}:${port};`), the manifest fetch
  (`/api/ucore/manifest`), the status poll (`/api/ucore/status`), the `ds`
  proxy, and the fabric-config fetch.
- Literal host, port from config, in about 25 template strings such as
  `` `http://127.0.0.1:${E.services.users.ports.http.api}/...` ``:
  6 for the Network API, 4 for the users API, 4 for the `uos-agent` IPC port,
  plus per-service backup import/export, support dump and storage calls.
  The `/api/v2/` proxy to `uos-agent` uses `hostname: "127.0.0.1"`, and its
  nginx upstream is `server 127.0.0.1:${E.uosAgent.apiHttpPort};`.
- `E.discovery.discoveryClientUrl` is a full URL (2 uses, no literal sibling).
- Listeners: `createServer(...).listen(port, "127.0.0.1", ...)` for IPC and
  `let t = "127.0.0.1"` for the gRPC bind.
- **Live test:** adding
  `services.users.host: ulp-go` and `controllers.network.host: unifi` to the
  override produced `server ulp-go:9080;` and `server unifi:8081;` in the
  generated upstream files, and also `server ulp-go:13080;` for the directory
  upstream. Port 13080 belongs to `unifi-directory`, so one `host` for the
  `users` entry cannot be right for all three of its ports
  (`api` 9080, `directoryService` 13080, `ucsService` 9580).

### ulp-go

Keys that are read next to a loopback default: `ucore.api`
(`NewUCoreAPIGeneric`, `pollEventWithWS`, `UcoreUcp4APIImpl.connect`),
`talk.api`, `protect.api`, `drive.api`, `user_assets.api`, `http.listen`,
`path.ulp_go.jsonrpc_sock`.

Literals with no key in the function:

| Literal | Function |
|---|---|
| `http://127.0.0.1:9680` | `credential_server/api.NewUcsAgentAPI` |
| `http://127.0.0.1:6080` | `uid_agent_api.NewUidAPI` |
| `http://127.0.0.1:13080` | `directory_service/api.NewDirectoryAPI` (two packages) |
| `http://127.0.0.1:9081` | `credential_server/api.NewUcsUpdateAPI`, `ProxyToIdentityUpdate` |
| `http://localhost:8081` | `go-network-api/site_api.NewDefaultSiteAPI` |
| `http://127.0.0.1:11081/api/...` | `UcorePackageInstallerImpl` (3 methods), `prepareUcoreProxy` |
| `ws://127.0.0.1:11081/ipc` | `identity/internal/service/ucore.(*UcoreUcp4APIImpl).connect` |
| table of 11 loopback URLs | `http_service.init` |

- `NewUcsAgentAPI` was read in disassembly: it calls
  `strings.TrimRight("http://127.0.0.1:9680", "/")` and stores the result in
  the HTTP client's host URL fields. No property lookup. The shipped key
  `ucs.agent.api` is read by one function only
  (`org_service.getDirectoryStatus`).
- **Live test:** with `ucore.api = http://unifi-core:11081`, `ulp-go` logged
  `init wsClient: url: ws://unifi-core:11081/mb` and held 4 connections to
  core's container IP, while 1 connection still went to `127.0.0.1:11081`.

### ucs-agent

- `ucore.api` is read by `ws_relay.(*WsRelayMiddleware).buildConfig` and
  `defaultFetchECConfig` (default `http://localhost:11081`). The key is not
  in the shipped `config.props`.
- `http://localhost:11081/mb` in `messagebox.NewMessageBoxService` and the
  three `UcorePackageInstallerImpl` URLs have no key.
- Reverse-proxy targets come from `proxy.services` in `config.props` (not
  traced further in code).
- Listen: `http.listen` in `http.NewServer`.

### unifi-identity-update

- Literals, no keys: `http://localhost:9080` (`ulp_service.newRestyClient`),
  `http://localhost:9680` (`ucs_agent_service.NewUcsAgentAPI`),
  `http://127.0.0.1:11081` (`ucore_service.NewUCoreAPI`, `GetUCoreInfo`),
  `https://localhost:443` (`GetUCoreFingerprint`), installer URLs.
- Listen (`internal/http.(*HttpService).prepare`): `127.0.0.1:%d`, or `:%d`
  when `http.debug` is true. That is the only reader of `http.debug`.

### uid-agent

- Literals, no keys: `http://127.0.0.1:11081` (`ulp/ucore.NewUCoreAPI`),
  `ws://127.0.0.1:11081/ipc`, `http://localhost:11081/mb`,
  `http://localhost:9080` (`ulp/api.newRestyClient`),
  `http://localhost:8081` (Network).
- Listen (`coms/http.(*HttpService).Prepare`, read in disassembly):
  `fmt.Sprintf("127.0.0.1:%d", viper.GetInt("http.port"))`, replaced by
  `:%d` if `viper.GetBool("http.debug")`. `http.debug` is also read by
  `middleware.AssertFromUniFiCore` and the agent setup/deactivate
  controllers.

### unifi-directory

- `ucore.api` in `ucore_service.NewUCoreAPIGeneric` (not in the shipped
  `config.props`); `http://127.0.0.1:8081` in
  `network_service.NewNetworkAPIGeneric` without a key.
- Listen: `127.0.0.1:%d` with `port.http` in `http.NewServer`; no listen key
  in the binary.

### unifi (Java)

- `ucoreApiBaseAddress()` is a Spring bean returning the constant
  `"http://127.0.0.1:11081/"`.
- `"http://127.0.0.1:9080/api" + path` (ulp-go client),
  `"http://127.0.0.1:11010/api/" + path` and
  `"http://127.0.0.1:11011/api/" + path` (`uos-agent` clients).
- Message box URLs are `"http://127.0.0.1:%s/mb/sub".formatted(port)`:
  port is a parameter, host is not.
- Local connector: `connector.setProperty("address", "127.0.0.1")`.
- `application.properties` in the jar has no address-related keys. Related
  property names in the classes: `unifi.http.port`, `unifi.https.port`,
  `unifi.local.http.port`, `unifi.postgresql.host`, `unifi.postgresql.port`.

### uos-agent

Both listeners build the socket address with
`mov DWORD PTR [r14+0xbaa], 0x100007f` (at `0x3d9ad2` and `0x3dba69`, the
only two such instructions in the binary); the port is loaded from a field.
No environment variable for the address was found.

### uos-discovery-client

Environment variables in the binary: `DISCOVERY_CLIENT_SERVER_HOST`
(default `127.0.0.1`), `DISCOVERY_CLIENT_DISABLE_DISCOVERY`,
`DISCOVERY_CLIENT_LOG_PATH`, `DISCOVERY_CLIENT_WSL_MACHINE_IP`.
**Live test:** with `DISCOVERY_CLIENT_SERVER_HOST=0.0.0.0` it listens on
`0.0.0.0:11002`.

## Limits of this analysis

- Static reading shows what a function does with a literal, not every path
  that could later replace the value. The two constructors read in
  disassembly had no such path; the others were classified by the absence of
  any config-key string in the function.
- `ulp-go`'s `http_service.init` table and the Network API library's
  non-default constructor (`NewSiteAPI`) were not traced to their callers.
- `proxy.services` (ucs-agent, identity-update) is assumed to work as its
  shipped value suggests.
- HTTP proxy environment variables are not a workaround: Go's default
  transport never proxies loopback destinations.

## If the services are ever separated again

These edges could use configuration instead of a bridge, with the caveats
above:

- `ulp-go`, `ucs-agent`, `unifi-directory` → core: `ucore.api`
  (core still needs the inbound bridge, since it listens on loopback only).
- core → `uos-discovery-client`: `discovery.discoveryClientUrl` plus
  `DISCOVERY_CLIENT_SERVER_HOST=0.0.0.0`. This is the only edge that needs no
  bridge on either side.
- `ulp-go` and `ucs-agent` listeners: `http.listen = 0.0.0.0` removes their
  inbound bridges, but exposes those ports to the whole docker network and
  changes the peer address the apps see (`http.trust.hosts` is
  `localhost,127.0.0.1,::1`).

Patching would be the other route: the stack already patches `service.js` at
boot, and the ~25 literal hosts there are textual. That is a code patch, not
configuration, and would have to be re-validated on every image upgrade.

## Re-checking after an upgrade

1. Beautify `service.js` and list `127.0.0.1`; compare the count and the
   `host: x = "127.0.0.1"` sites.
2. For each Go binary, list loopback URL literals and the functions that load
   them; look for new `<service>.api` keys.
3. In the Java jar, grep the classes of `internal-dependencies.jar` for
   `127.0.0.1` and decompile the hits.
4. For the Rust agents, grep for new environment variable names and for
   `0x100007f` immediates.
