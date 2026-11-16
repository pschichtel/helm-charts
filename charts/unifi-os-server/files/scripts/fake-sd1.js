'use strict';
// Minimal fake org.freedesktop.systemd1 provider for unifi-core under docker.
// Contract used by unifi-core (service.js A$/bf watcher + rut/Rwe factory):
//   Manager: Introspect, Subscribe(), Unsubscribe(), LoadUnit(name) -> object path
//   Unit:    Introspect, org.freedesktop.DBus.Properties Get(iface, "ActiveState"|"StatusText"|...)
// Everything else: no-op success (app only reads; never Starts/Stops units).
let dbus = null;
for (const p of [
  '/usr/share/unifi-core/app/node_modules/dbus-next',
  '/usr/share/unifi-core/app/node_modules/@jellybrick/dbus-next',
]) {
  try { dbus = require(p); break; } catch (e) {}
}
if (!dbus) { console.error('cannot require dbus-next'); process.exit(1); }
const { systemBus, Message, Variant, MessageType, RequestNameReply } = dbus;

const MANAGER = 'org.freedesktop.systemd1';
const MPATH = '/org/freedesktop/systemd1';
const UNIT_PREFIX = MPATH + '/unit/';
const UNITS = {};

function esc(name) {
  return String(name).replace(/[./]/g, '_').replace(/[^a-zA-Z0-9_]/g, c => '_' + c.charCodeAt(0).toString(16));
}
function unitPath(name) { return UNIT_PREFIX + esc(name); }

const MANAGER_XML = `<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.freedesktop.systemd1.Manager">
    <method name="Subscribe"><arg name="cookie" type="i" direction="out"/></method>
    <method name="Unsubscribe"><arg name="cookie" type="i" direction="out"/></method>
    <method name="LoadUnit"><arg name="name" type="s" direction="in"/><arg name="unit_path" type="o" direction="out"/></method>
    <method name="GetUnit"><arg name="name" type="s" direction="in"/><arg name="unit_path" type="o" direction="out"/></method>
    <property name="Version" type="s" access="read"/>
    <property name="State" type="s" access="read"/>
    <signal name="UnitNew"><arg type="s"/><arg type="o"/></signal>
    <signal name="UnitRemoved"><arg type="s"/><arg type="o"/></signal>
    <signal name="UnitFilesChanged"><arg type="b"/></signal>
  </interface>
</node>`;

const UNIT_XML = `<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="Get"><arg name="interface_name" type="s" direction="in"/><arg name="property_name" type="s" direction="in"/><arg name="value" type="v" direction="out"/></method>
    <method name="Set"><arg name="interface_name" type="s" direction="in"/><arg name="property_name" type="s" direction="in"/><arg name="value" type="v" direction="in"/></method>
    <method name="GetAll"><arg name="interface_name" type="s" direction="in"/><arg name="props" type="a{sv}" direction="out"/></method>
    <signal name="PropertiesChanged"><arg name="interface_name" type="s"/><arg name="changed_properties" type="a{sv}"/><arg name="invalidated_properties" type="as"/></signal>
  </interface>
  <interface name="org.freedesktop.systemd1.Unit">
    <property name="Id" type="s" access="read"/>
    <property name="ActiveState" type="s" access="read"/>
    <property name="SubState" type="s" access="read"/>
    <property name="LoadState" type="s" access="read"/>
    <property name="StatusText" type="s" access="read"/>
    <property name="MainPID" type="u" access="read"/>
    <property name="Unit" type="s" access="read"/>
  </interface>
  <interface name="org.freedesktop.systemd1.Service">
    <method name="Start"><arg name="mode" type="s" direction="in"/><arg name="job_path" type="o" direction="out"/></method>
    <method name="Stop"><arg name="mode" type="s" direction="in"/><arg name="job_path" type="o" direction="out"/></method>
    <method name="Restart"><arg name="mode" type="s" direction="in"/><arg name="job_path" type="o" direction="out"/></method>
    <method name="TryRestart"><arg name="mode" type="s" direction="in"/><arg name="job_path" type="o" direction="out"/></method>
    <method name="Reload"><arg name="mode" type="s" direction="in"/><arg name="job_path" type="o" direction="out"/></method>
    <method name="TryReload"><arg name="mode" type="s" direction="in"/><arg name="job_path" type="o" direction="out"/></method>
    <method name="Kill"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <property name="ExecMainStatus" type="i" access="read"/>
    <property name="ExecMainStartTimestamp" type="t" access="read"/>
    <property name="MainPID" type="u" access="read"/>
    <property name="NRestarts" type="u" access="read"/>
    <property name="ActiveState" type="s" access="read"/>
    <property name="SubState" type="s" access="read"/>
    <property name="LoadState" type="s" access="read"/>
    <property name="StatusText" type="s" access="read"/>
  </interface>
</node>`;

function getProp(name, prop) {
  switch (prop) {
    case 'ActiveState': return 'active';
    case 'SubState': return 'running';
    case 'LoadState': return 'loaded';
    case 'Id': case 'Unit': return name;
    case 'MainPID': return 1;
    case 'ActiveSince': return Math.floor(Date.now() / 1000);
    case 'StatusText': return '';
    default: return '';
  }
}
function mgrProp(prop) {
  switch (prop) {
    case 'Version': return '252';
    case 'State': return 'running';
    default: return '';
  }
}
function mkDict(get) {
  const dict = {};
  for (const k of ['ActiveState', 'SubState', 'LoadState', 'Id', 'MainPID', 'StatusText']) dict[k] = get(k);
  return dict;
}

function main() {
  const bus = systemBus();
  bus.on('error', e => console.error('BUS-ERROR', e && e.message ? e.message : e));
  bus.on('connect', async () => {
    try {
      const r = await bus.requestName(MANAGER, 0);
      console.log('requestName reply=' + r);
      if (RequestNameReply && r !== RequestNameReply.PRIMARY_OWNER) {
        console.error('not primary owner');
        process.exit(1);
      }
      console.log('FAKE-SD1-READY');
    } catch (e) { console.error('requestName failed', e); process.exit(1); }
  });
  bus.on('message', msg => {
    if (msg.type !== MessageType.METHOD_CALL) return;
    const path = msg.path, member = msg.member, body = msg.body || [];
    const ok = (sig, b) => { try { bus.send(Message.newMethodReturn(msg, sig, b || [])); } catch (e) { console.error('send fail', e); } };
    const err = (code, txt) => { try { bus.send(Message.newError(msg, code, txt || code)); } catch (e) { console.error('send fail', e); } };
    try {
      if (member === 'Introspect') {
        let xml = '<node/>';
        if (path === MPATH) xml = MANAGER_XML;
        else if (path.startsWith(UNIT_PREFIX)) xml = UNIT_XML;
        return ok('s', [xml]);
      }
      if (path === MPATH) {
        if (member === 'Subscribe' || member === 'Unsubscribe') return ok('i', [0]);
        if (member === 'LoadUnit' || member === 'GetUnit') {
          const name = String(body[0] || '');
          UNITS[unitPath(name)] = name;
          console.log('LoadUnit/GetUnit', name);
          return ok('o', [unitPath(name)]);
        }
        if (member === 'Get') {
          const v = mgrProp(String(body.length > 1 ? body[1] : body[0]));
          return ok('v', [new Variant('s', v)]);
        }
        if (member === 'GetAll') {
          try { return ok('a{sv}', [new Variant('a{sv}', { Version: '252', State: 'running' })]); }
          catch (e) { return err('org.freedesktop.DBus.Error.Failed', 'GetAll unsupported'); }
        }
        if (member === 'ListUnits' || member === 'GetUnits' || member === 'ListUnitFiles' || member === 'ListJobs') return ok('a(susoBst)', []);
        if (member === 'GetUnitFileState') return ok('s', ['enabled']);
        console.log('manager no-op', member);
        return ok(''); // unknown manager method -> pretend success
      }
      if (path.startsWith(UNIT_PREFIX)) {
        const name = UNITS[path] || 'unit.service';
        if (member === 'Get') {
          const prop = String(body.length > 1 ? body[1] : body[0]);
          const v = getProp(name, prop);
          return ok('v', [new Variant(typeof v === 'number' ? 'u' : 's', v)]);
        }
        if (member === 'Set') return ok('');
        if (member === 'GetAll') {
          try { return ok('a{sv}', [new Variant('a{sv}', mkDict(k => getProp(name, k)))]); }
          catch (e) { console.error('GetAll variant fail', e); return err('org.freedesktop.DBus.Error.Failed', 'GetAll unsupported'); }
        }
        if (['Start', 'Stop', 'Restart', 'TryRestart', 'Reload', 'TryReload'].includes(member)) {
          console.log('unit job', path, member);
          return ok('o', ['/org/freedesktop/systemd1/job/1']);
        }
        console.log('unit method no-op', path, member);
        return ok(''); // Kill/... -> pretend success
      }
      console.log('UNHANDLED', path, member);
      return err('org.freedesktop.DBus.Error.UnknownObject');
    } catch (e) {
      console.error('handle error', e);
      return err('org.freedesktop.DBus.Error.Failed', String(e && e.message || e));
    }
  });
}
main();
