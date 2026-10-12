/**
 * Tailscale identity auth (backend/api/auth.ts), ported from familiar's tests
 * (~/Repositories/familiar/test/server/auth.test.ts) with enchiridion's
 * differences: the devices file is the on/off switch (with a grace while it is
 * replaced), loopback without a proxy is `local` when its Host names this
 * machine, X-Forwarded-For counts only when Host is the API's name, and this
 * server's own node is admitted. Then the real app over HTTP: /info open, /me,
 * the 401's shape, CORS on a 401, other sites' pages refused (but archived
 * pages' fonts loaded, and archives sandboxed), every other path gated, and
 * updates of deleted records refused. The real
 * tailscale CLI never runs: the units inject `exec`, and the app gets a stand-in
 * shell script through ENCHIRIDION_TAILSCALE.
 */
import { mkdir, mkdtemp, readFile, rm, utimes, writeFile } from 'node:fs/promises';
import type { IncomingHttpHeaders, IncomingMessage, ServerResponse } from 'node:http';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Express } from 'express';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import {
  apiHostFrom,
  ARCHIVE_CSP,
  createTailscaleAuth,
  DEFAULT_API_HOST,
  devicesPathFrom,
  FORBIDDEN_ORIGIN,
  forwardedTailnetAddress,
  isArchiveAsset,
  isLocalRequest,
  isLoopback,
  isLoopbackHost,
  isTailnetAddress,
  isWebOrigin,
  MISSING_GRACE_MS,
  parseDevices,
  parseSelf,
  parseWhois,
  webOriginsFrom,
  type PeerRequest,
  type TailscaleExec,
} from '@api/auth';

/** A tailnet node as `tailscale whois --json` describes it (ids and names made up). */
interface FakeNode {
  address: string;
  id: string;
  /** Hostinfo.Hostname. */
  hostname: string;
  /** Node.Name: the MagicDNS name with its trailing dot; "" for none. */
  dns: string;
  /** UserProfile.LoginName; "" for none. */
  user: string;
}

const USER = 'someone@example.com';

/** This server, a listed phone (which, like iPhones do, calls itself "localhost"), an unlisted tablet, and a node with no MagicDNS name. */
const TAILNET = {
  self: 'nSe1fVoy4g11CNTRL',
  server: {
    address: '100.64.0.1',
    id: 'nSe1fVoy4g11CNTRL',
    hostname: 'Voyager',
    dns: 'voyager.example.ts.net.',
    user: USER,
  },
  phone: {
    address: '100.101.102.103',
    id: 'nPh0neAbcd11CNTRL',
    hostname: 'localhost',
    dns: 'vern.example.ts.net.',
    user: USER,
  },
  tablet: {
    address: '100.111.112.113',
    id: 'nTab1etXyz11CNTRL',
    hostname: 'iPad',
    dns: 'ipad.example.ts.net.',
    user: USER,
  },
  bare: {
    address: 'fd7a:115c:a1e0::a1b2:c3d4',
    id: 'nBareNode011CNTRL',
    hostname: '  MacBook Air ',
    dns: '',
    user: '',
  },
} as const satisfies { self: string } & Record<string, string | FakeNode>;

/** The whois answer for a node, in the CLI's shape (tailscale 1.102). */
const whoisJson = (node: FakeNode): string =>
  JSON.stringify({
    Node: {
      ID: 1234567890,
      StableID: node.id,
      Name: node.dns,
      Addresses: [`${node.address}/32`],
      Hostinfo: { OS: 'iOS', Hostname: node.hostname },
      ComputedName: node.dns.split('.')[0],
    },
    UserProfile: { ID: 987654321, LoginName: node.user, DisplayName: 'someone' },
    CapMap: null,
  });

/** The status answer: Self.ID is this server. */
const statusJson = (self: string = TAILNET.self): string =>
  JSON.stringify({ BackendState: 'Running', Self: { ID: self, HostName: 'Voyager' }, Peer: {} });

/** A fake CLI over the test tailnet: whois fails like the real one for an unknown address. `calls` records each run. */
function fakeTailscale(
  nodes: readonly FakeNode[] = [TAILNET.server, TAILNET.phone, TAILNET.tablet, TAILNET.bare],
) {
  const calls: string[][] = [];
  const exec: TailscaleExec = async (args) => {
    calls.push([...args]);
    if (args[0] === 'status') return statusJson();
    const node = nodes.find((n) => n.address === args[2]);
    if (node === undefined) {
      throw new Error(`Command failed: tailscale whois --json ${args[2]}\nno match for IP:port`);
    }
    return whoisJson(node);
  };
  return { exec, calls };
}

/** A request as the scheme sees it: the TCP peer and the headers. */
const from = (
  remoteAddress: string | undefined,
  headers: IncomingHttpHeaders = {},
): PeerRequest => ({
  socket: { remoteAddress },
  headers,
});

/** The API's public name: Caddy passes it through as Host, with X-Forwarded-For set to the device's address. */
const API = DEFAULT_API_HOST;

const viaCaddy = (forwarded: string) =>
  from('127.0.0.1', { host: API, 'x-forwarded-for': forwarded });

let dir: string;
beforeAll(async () => {
  dir = await mkdtemp(join(tmpdir(), 'ench-auth-'));
});
afterAll(() => rm(dir, { recursive: true, force: true }));

describe('which address the scheme judges', () => {
  it('counts 127/8, ::1 and ::ffff:127.x as loopback, and nothing else', () => {
    for (const address of [
      '127.0.0.1',
      '127.0.0.2',
      '127.255.0.9',
      '::1',
      '::ffff:127.0.0.1',
      '::FFFF:127.0.0.1',
    ]) {
      expect([address, isLoopback(address)]).toEqual([address, true]);
    }
    for (const address of [
      undefined,
      '',
      '0.0.0.0',
      '::',
      'localhost',
      '100.86.62.81',
      '192.168.86.53',
      '::ffff:100.86.62.81',
      '128.0.0.1',
      '::2',
    ]) {
      expect([address, isLoopback(address)]).toEqual([address, false]);
    }
  });

  it('knows the tailnet ranges, 100.64.0.0/10 and fd7a:115c:a1e0::/48, and nothing else', () => {
    for (const address of [
      '100.64.0.0',
      '100.86.62.81',
      '100.127.255.255',
      'fd7a:115c:a1e0::1',
      'FD7A:115C:A1E0:ab12::1',
    ]) {
      expect([address, isTailnetAddress(address)]).toEqual([address, true]);
    }
    for (const address of [
      '100.63.255.255',
      '100.128.0.0',
      '99.64.0.1',
      '10.0.0.1',
      'fd7b:115c:a1e0::1',
      'fd7a:115d:a1e0::1',
      '::ffff:100.86.62.81',
      '100.86.62.81/32',
      '[fd7a:115c:a1e0::1]',
      'not an address',
      '',
    ]) {
      expect([address, isTailnetAddress(address)]).toEqual([address, false]);
    }
  });

  it('reads X-Forwarded-For only from a loopback peer, and only one tailnet address', () => {
    for (const peer of ['127.0.0.1', '::1', '::ffff:127.0.0.1', '127.0.0.2']) {
      expect([
        peer,
        forwardedTailnetAddress(from(peer, { host: API, 'x-forwarded-for': '100.86.62.81' }), API),
      ]).toEqual([peer, '100.86.62.81']);
    }
    expect(forwardedTailnetAddress(viaCaddy(' fd7a:115c:a1e0::a501:3e51 '), API)).toBe(
      'fd7a:115c:a1e0::a501:3e51',
    );
    // Not loopback: a tailnet or LAN process talking to the port directly. The header is its own claim, so it's ignored.
    for (const peer of ['100.86.62.81', '192.168.86.53', '::ffff:100.86.62.81', undefined]) {
      expect([
        peer,
        forwardedTailnetAddress(from(peer, { host: API, 'x-forwarded-for': '100.86.62.81' }), API),
      ]).toEqual([peer, undefined]);
    }
    // Loopback, but no single tailnet address.
    for (const forwarded of [
      '',
      '100.86.62.81, 10.0.0.1',
      '10.0.0.1, 100.86.62.81',
      '100.86.62.81,100.86.62.82',
      '192.168.86.53',
      '100.63.255.255',
      '100.128.0.0',
      '99.64.0.1',
      'fd7b:115c:a1e0::1',
      'fd7a:115d:a1e0::1',
      '::ffff:100.86.62.81',
      '100.86.62.81/32',
      '[fd7a:115c:a1e0::1]',
      'not an address',
    ]) {
      expect([forwarded, forwardedTailnetAddress(viaCaddy(forwarded), API)]).toEqual([
        forwarded,
        undefined,
      ]);
    }
    expect(forwardedTailnetAddress(from('127.0.0.1', { host: API }), API)).toBeUndefined();
    // Two headers arrive as a list.
    expect(
      forwardedTailnetAddress(
        from('127.0.0.1', { host: API, 'x-forwarded-for': ['100.86.62.81', '100.86.62.82'] }),
        API,
      ),
    ).toBeUndefined();
  });

  it('reads X-Forwarded-For only when Host is the API name Caddy passes through', () => {
    // Any case, any port: still the API's name.
    for (const host of [API, `${API}:443`, 'Enchiridion-API.chsmc.tools']) {
      expect([
        host,
        forwardedTailnetAddress(
          from('127.0.0.1', { host, 'x-forwarded-for': '100.86.62.81' }),
          API,
        ),
      ]).toEqual([host, '100.86.62.81']);
    }
    // A page in a browser on this machine whose name was rebound to 127.0.0.1 can set the header,
    // but its Host names its own site. Nor does a local process's Host make the header Caddy's.
    for (const host of [
      undefined,
      '',
      'rebind.evil.example:4321',
      `${API}.evil.example`,
      `evil.${API}`,
      'localhost:4321',
      '127.0.0.1:4321',
      'enchiridion.chsmc.tools',
    ]) {
      const headers: IncomingHttpHeaders = { 'x-forwarded-for': '100.86.62.81' };
      if (host !== undefined) headers.host = host;
      expect([host, forwardedTailnetAddress(from('127.0.0.1', headers), API)]).toEqual([
        host,
        undefined,
      ]);
    }
    // Another configured name.
    expect(forwardedTailnetAddress(viaCaddy('100.86.62.81'), 'api.example.test')).toBeUndefined();
    expect(
      forwardedTailnetAddress(
        from('::1', { host: 'api.example.test', 'x-forwarded-for': '100.86.62.81' }),
        'API.example.test:8443',
      ),
    ).toBe('100.86.62.81');
  });

  it('takes the API name from ENCHIRIDION_API_HOST, else enchiridion-api.chsmc.tools', () => {
    expect(apiHostFrom({})).toBe('enchiridion-api.chsmc.tools');
    expect(apiHostFrom({ ENCHIRIDION_API_HOST: '  ' })).toBe('enchiridion-api.chsmc.tools');
    expect(apiHostFrom({ ENCHIRIDION_API_HOST: ' API.example.test:8443 ' })).toBe(
      'api.example.test',
    );
  });

  it('takes a Host naming localhost, 127/8 or [::1], with any port, for this machine, and no other name', () => {
    for (const host of [
      'localhost',
      'localhost:4321',
      'LocalHost:4321',
      '127.0.0.1',
      '127.0.0.1:4321',
      '127.1.2.3:80',
      '[::1]',
      '[::1]:4321',
    ]) {
      expect([host, isLoopbackHost(host)]).toEqual([host, true]);
    }
    for (const host of [
      '',
      'rebind.evil.example',
      'rebind.evil.example:4321',
      'localhost.evil.example',
      'evil.localhost:4321',
      'localhost.',
      '127.0.0.1.evil.example',
      '100.127.164.4:4321',
      'enchiridion-api.chsmc.tools',
      '[::2]:4321',
      '[::ffff:127.0.0.1]:4321',
    ]) {
      expect([host, isLoopbackHost(host)]).toEqual([host, false]);
    }
  });

  it('counts a loopback peer without X-Forwarded-For as local only when its Host names this machine', () => {
    expect(isLocalRequest(from('127.0.0.1'))).toBe(true); // no browser leaves Host out
    expect(isLocalRequest(from('::1', { host: 'localhost:4321' }))).toBe(true);
    expect(isLocalRequest(from('::ffff:127.0.0.1', { host: '127.0.0.1:4321' }))).toBe(true);
    // A page whose name was rebound to 127.0.0.1 sends that name.
    expect(isLocalRequest(from('127.0.0.1', { host: 'rebind.evil.example:4321' }))).toBe(false);
    expect(isLocalRequest(viaCaddy(TAILNET.phone.address))).toBe(false);
    expect(isLocalRequest(from('192.168.86.53', { host: 'localhost:4321' }))).toBe(false);
  });
});

describe("the web app's origins", () => {
  it("lets through only an archived page's own assets, never a fetch() or another path", () => {
    const asset = (method: string, path: string, dest?: string) =>
      isArchiveAsset({
        method,
        path,
        headers: dest === undefined ? {} : { 'sec-fetch-dest': dest },
      });
    for (const dest of ['font', 'image', 'style', 'script', 'audio', 'video', 'track']) {
      expect([dest, asset('GET', '/archives/a/assets/f.woff2', dest)]).toEqual([dest, true]);
    }
    expect(asset('HEAD', '/archives/a/assets/f.woff2', 'font')).toBe(true);
    for (const dest of [undefined, '', 'empty', 'document', 'iframe', 'json', 'worker', 'Font']) {
      expect([dest, asset('GET', '/archives/a/assets/f.woff2', dest)]).toEqual([dest, false]);
    }
    for (const [method, path] of [
      ['POST', '/archives/a/assets/f.woff2'],
      ['GET', '/archives'],
      ['GET', '/record/1'],
      ['GET', '/uploads/a.png'],
      ['GET', '/search/archives/x'],
    ] as const) {
      expect([method, path, asset(method, path, 'font')]).toEqual([method, path, false]);
    }
  });

  it('are the production web app, plus the Vite dev server on loopback at FRONTEND_PORT', () => {
    const site = 'https://enchiridion.chsmc.tools';
    expect(webOriginsFrom({})).toEqual({ site, dev: new Set() });
    expect(webOriginsFrom({ FRONTEND_PORT: 'not a port' })).toEqual({ site, dev: new Set() });
    expect(webOriginsFrom({ FRONTEND_PORT: ' 3456 ' })).toEqual({
      site,
      dev: new Set(['http://localhost:3456', 'http://127.0.0.1:3456', 'http://[::1]:3456']),
    });
  });

  it("takes a dev server's origin only from a local process, since localhost is any device's own", () => {
    const origins = webOriginsFrom({ FRONTEND_PORT: '3456' });
    const local = from('127.0.0.1', { host: 'localhost:4321' });
    // A page at localhost:3456 on a listed device, calling the API through Caddy.
    const device = viaCaddy(TAILNET.phone.address);
    expect(isWebOrigin(origins, 'https://enchiridion.chsmc.tools', local)).toBe(true);
    expect(isWebOrigin(origins, 'https://enchiridion.chsmc.tools', device)).toBe(true);
    for (const dev of ['http://localhost:3456', 'http://127.0.0.1:3456', 'http://[::1]:3456']) {
      expect([dev, isWebOrigin(origins, dev, local)]).toEqual([dev, true]);
      expect([dev, isWebOrigin(origins, dev, from('::1'))]).toEqual([dev, true]);
      expect([dev, isWebOrigin(origins, dev, device)]).toEqual([dev, false]);
      expect([dev, isWebOrigin(origins, dev, from('192.168.86.53'))]).toEqual([dev, false]);
      expect([
        dev,
        isWebOrigin(origins, dev, from('127.0.0.1', { host: 'rebind.example' })),
      ]).toEqual([dev, false]);
    }
    for (const other of ['http://localhost:8080', 'https://evil.example', 'null']) {
      expect([other, isWebOrigin(origins, other, local)]).toEqual([other, false]);
    }
  });
});

describe('parsing', () => {
  it('reads a whois answer by the CLI field names, naming a device by its MagicDNS label first', () => {
    // The phone's hostname is "localhost"; its MagicDNS label is what people call it.
    expect(parseWhois(whoisJson(TAILNET.phone))).toEqual({
      device: { id: TAILNET.phone.id, name: 'vern' },
      user: USER,
    });
    // No MagicDNS name: the hostname, trimmed. No login: user null.
    expect(parseWhois(whoisJson(TAILNET.bare))).toEqual({
      device: { id: TAILNET.bare.id, name: 'MacBook Air' },
      user: null,
    });
    expect(
      parseWhois(JSON.stringify({ Node: { StableID: 'nX', Name: 'solo.' }, UserProfile: {} })),
    ).toEqual({ device: { id: 'nX', name: 'solo' }, user: null });
    expect(
      parseWhois(
        JSON.stringify({ Node: { StableID: 'nX', Name: '.', Hostinfo: { Hostname: 'Studio' } } }),
      ),
    ).toEqual({ device: { id: 'nX', name: 'Studio' }, user: null });
    // Neither: the id.
    expect(
      parseWhois(JSON.stringify({ Node: { StableID: 'nX', Hostinfo: { Hostname: '  ' } } })),
    ).toEqual({ device: { id: 'nX', name: 'nX' }, user: null });
    for (const bad of [
      '{}',
      '{"Node":{}}',
      '{"Node":{"StableID":""}}',
      '{"Node":{"StableID":5}}',
      'null',
      '[]',
      '5',
      'not json',
    ]) {
      expect(() => parseWhois(bad)).toThrow();
    }
  });

  it('reads the status answer', () => {
    expect(parseSelf(statusJson('nSelf'))).toBe('nSelf');
    for (const bad of ['{}', '{"Self":{}}', '{"Self":{"ID":""}}', 'null', 'not json'])
      expect(() => parseSelf(bad)).toThrow();
  });

  it('reads the devices file: one id per line, an optional name, # comments and blank lines', () => {
    const parsed = parseDevices(
      [
        '# the apps',
        '',
        'nPhone11CNTRL  the phone  # since 2026',
        '  nTablet11CNTRL\tthe tablet',
        'nBare11CNTRL',
        '   ',
        '#nNope11CNTRL',
        'nWin11CNTRL\r',
      ].join('\n'),
    );
    expect([...parsed]).toEqual([
      ['nPhone11CNTRL', 'the phone'],
      ['nTablet11CNTRL', 'the tablet'],
      ['nBare11CNTRL', ''],
      ['nWin11CNTRL', ''],
    ]);
    expect(parseDevices('')).toEqual(new Map());
  });

  it('finds the devices file in ENCHIRIDION_DEVICES, else ~/.enchiridion/devices', () => {
    const fallback = join(homedir(), '.enchiridion', 'devices');
    expect(devicesPathFrom({})).toBe(fallback);
    expect(devicesPathFrom({ ENCHIRIDION_DEVICES: '  ' })).toBe(fallback);
    expect(devicesPathFrom({ ENCHIRIDION_DEVICES: '/srv/enchiridion/devices' })).toBe(
      '/srv/enchiridion/devices',
    );
    expect(devicesPathFrom({ ENCHIRIDION_DEVICES: '~/elsewhere/devices' })).toBe(
      join(homedir(), 'elsewhere', 'devices'),
    );
  });
});

describe('the scheme', () => {
  let n = 0;

  /**
   * A scheme over the fake tailnet, on a clock the test moves. `listed` is
   * written to a fresh devices file; null leaves the file absent (off). Its
   * timers run on that clock: `tick` runs each one that falls due, at its time,
   * and waits for it. `timers: false` drops them, as a stalled event loop would.
   */
  const scheme = async (
    listed: readonly string[] | null,
    options: { exec?: TailscaleExec; timeoutMs?: number; timers?: boolean } = {},
  ) => {
    n += 1;
    const devicesPath = join(dir, `devices-${n}`);
    if (listed !== null)
      await writeFile(devicesPath, listed.map((id) => `${id} a device\n`).join(''));
    const fake = fakeTailscale();
    const log: string[] = [];
    let now = 1_000_000;
    const timers: { at: number; run: () => Promise<unknown> }[] = [];
    const auth = createTailscaleAuth({
      devicesPath,
      exec: options.exec ?? fake.exec,
      log: (line) => log.push(line),
      timeoutMs: options.timeoutMs ?? 2000,
      now: () => now,
      schedule: (run, ms) => {
        if (options.timers !== false) timers.push({ at: now + ms, run });
      },
    });
    await auth.enabled(); // the read it starts with
    const tick = async (ms: number) => {
      const until = now + ms;
      for (;;) {
        timers.sort((a, b) => a.at - b.at);
        const due = timers[0];
        if (due === undefined || due.at > until) break;
        timers.shift();
        now = due.at;
        await due.run();
      }
      now = until;
    };
    return { auth, devicesPath, calls: fake.calls, log, tick, timers };
  };

  const onOff = (log: string[]) => log.filter((line) => /^\[auth\] tailscale (on|off):/.test(line));

  it('is off without a devices file: open to everyone, says so once, and runs no CLI', async () => {
    const s = await scheme(null);
    expect(await s.auth.enabled()).toBe(false);
    for (const req of [
      from('127.0.0.1'),
      viaCaddy(TAILNET.tablet.address),
      from('192.168.86.53', { 'x-forwarded-for': '1.2.3.4' }),
    ]) {
      expect(await s.auth.principal(req)).toEqual({ scheme: 'open' });
    }
    expect(s.calls).toEqual([]);
    expect(s.log).toEqual([`[auth] tailscale off: no devices file at ${s.devicesPath}`]);
  });

  it('is on while the devices file exists, even empty, following it being created and deleted', async () => {
    const s = await scheme(null);
    await writeFile(s.devicesPath, '');
    expect(await s.auth.enabled()).toBe(true);
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toEqual({
      refused: { id: TAILNET.phone.id, name: 'vern' },
    });
    await writeFile(s.devicesPath, `${TAILNET.phone.id} the phone\n`);
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toMatchObject({
      scheme: 'tailscale',
    });
    // Deleted: off again, the API open, once it has stayed missing for the grace.
    await rm(s.devicesPath);
    expect(await s.auth.enabled()).toBe(true);
    await s.tick(MISSING_GRACE_MS);
    expect(await s.auth.enabled()).toBe(false);
    expect(await s.auth.principal(viaCaddy(TAILNET.tablet.address))).toEqual({ scheme: 'open' });
    await writeFile(s.devicesPath, `${TAILNET.phone.id}\n`);
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toMatchObject({
      scheme: 'tailscale',
    });
    const off = `[auth] tailscale off: no devices file at ${s.devicesPath}`;
    const on = `[auth] tailscale on: ${s.devicesPath}`;
    expect(onOff(s.log)).toEqual([off, on, off, on]);
  });

  it('keeps the allowlist while the devices file is replaced, so a save never opens the API', async () => {
    const s = await scheme([TAILNET.phone.id]);
    const refused = { refused: { id: TAILNET.tablet.id, name: 'ipad' } };
    // An editor renames the file away and writes a new one: missing for a moment.
    await rm(s.devicesPath);
    expect(await s.auth.principal(viaCaddy(TAILNET.tablet.address))).toEqual(refused);
    expect(await s.auth.principal(from('192.168.86.53'))).toBeUndefined();
    await s.tick(MISSING_GRACE_MS - 1);
    expect(await s.auth.principal(viaCaddy(TAILNET.tablet.address))).toEqual(refused);
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toMatchObject({
      scheme: 'tailscale',
    });
    // Back, listing the tablet now: never off in between.
    await writeFile(s.devicesPath, `${TAILNET.tablet.id} the tablet\n`);
    expect(await s.auth.principal(viaCaddy(TAILNET.tablet.address))).toMatchObject({
      scheme: 'tailscale',
    });
    // Each disappearance gets its own grace.
    await s.tick(10 * MISSING_GRACE_MS);
    await rm(s.devicesPath);
    expect(await s.auth.enabled()).toBe(true);
    await s.tick(MISSING_GRACE_MS - 1);
    expect(await s.auth.enabled()).toBe(true);
    await s.tick(1);
    expect(await s.auth.enabled()).toBe(false);
    expect(onOff(s.log)).toEqual([
      `[auth] tailscale on: ${s.devicesPath}`,
      `[auth] tailscale off: no devices file at ${s.devicesPath}`,
    ]);
  });

  it('never counts a missing file from an earlier save toward a later one, request or not', async () => {
    const stranger = viaCaddy(TAILNET.tablet.address);
    const refused = { refused: { id: TAILNET.tablet.id, name: 'ipad' } };
    // A request lands in one save's gap; the file is back before the next request, and
    // another save's gap catches the next request long after.
    for (const timers of [true, false]) {
      const s = await scheme([TAILNET.phone.id], { timers });
      await rm(s.devicesPath);
      expect([timers, await s.auth.principal(stranger)]).toEqual([timers, refused]);
      await writeFile(s.devicesPath, `${TAILNET.phone.id}\n`);
      await s.tick(10 * MISSING_GRACE_MS);
      await rm(s.devicesPath);
      expect([timers, await s.auth.principal(stranger)]).toEqual([timers, refused]);
      expect([timers, await s.auth.enabled()]).toEqual([timers, true]);
      expect(onOff(s.log)).toEqual([`[auth] tailscale on: ${s.devicesPath}`]);
    }
  });

  it('turns off once the file has stayed missing, with no request after the first', async () => {
    const s = await scheme([TAILNET.phone.id]);
    await rm(s.devicesPath);
    expect(await s.auth.enabled()).toBe(true);
    // The re-checks every quarter of the grace see it still gone.
    await s.tick(MISSING_GRACE_MS - 1);
    expect(onOff(s.log)).toEqual([`[auth] tailscale on: ${s.devicesPath}`]);
    await s.tick(1);
    expect(onOff(s.log)).toEqual([
      `[auth] tailscale on: ${s.devicesPath}`,
      `[auth] tailscale off: no devices file at ${s.devicesPath}`,
    ]);
    expect(s.timers).toEqual([]);
    expect(await s.auth.principal(viaCaddy(TAILNET.tablet.address))).toEqual({ scheme: 'open' });
  });

  it('re-checks on real timers by default', async () => {
    n += 1;
    const devicesPath = join(dir, `devices-${n}`);
    await writeFile(devicesPath, `${TAILNET.phone.id}\n`);
    const log: string[] = [];
    const auth = createTailscaleAuth({
      devicesPath,
      exec: fakeTailscale().exec,
      log: (line) => log.push(line),
      missingGraceMs: 200,
    });
    expect(await auth.enabled()).toBe(true);
    await rm(devicesPath);
    expect(await auth.enabled()).toBe(true);
    // No request from here on: the timers alone find it gone for the grace (a late one starts it over).
    const deadline = Date.now() + 10_000;
    while (!onOff(log).some((line) => line.includes(' off: ')) && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    expect(onOff(log)).toEqual([
      `[auth] tailscale on: ${devicesPath}`,
      `[auth] tailscale off: no devices file at ${devicesPath}`,
    ]);
  });

  it('starts the grace over after a gap in the checks longer than half of it', async () => {
    // No re-checks (an event loop held up): only requests check.
    const s = await scheme([TAILNET.phone.id], { timers: false });
    await rm(s.devicesPath);
    expect(await s.auth.enabled()).toBe(true);
    await s.tick(MISSING_GRACE_MS / 2 + 1);
    expect(await s.auth.enabled()).toBe(true); // too long after: the grace starts here
    await s.tick(MISSING_GRACE_MS / 2);
    expect(await s.auth.enabled()).toBe(true);
    await s.tick(MISSING_GRACE_MS / 2);
    expect(await s.auth.enabled()).toBe(false); // missing at every check over the grace
  });

  it("admits loopback with no X-Forwarded-For as local, and refuses a peer that isn't loopback", async () => {
    const s = await scheme([TAILNET.phone.id]);
    for (const peer of ['127.0.0.1', '::1', '::ffff:127.0.0.1']) {
      expect([peer, await s.auth.principal(from(peer))]).toEqual([peer, { scheme: 'local' }]);
      expect([peer, await s.auth.principal(from(peer, { host: 'localhost:4321' }))]).toEqual([
        peer,
        { scheme: 'local' },
      ]);
    }
    // A browser on this machine whose page's name was rebound to 127.0.0.1: not a local process,
    // nor, though it sets X-Forwarded-For to this server's own address, a forwarded device.
    expect(
      await s.auth.principal(from('127.0.0.1', { host: 'rebind.evil.example:4321' })),
    ).toBeUndefined();
    expect(
      await s.auth.principal(
        from('127.0.0.1', {
          host: 'rebind.evil.example:4321',
          'x-forwarded-for': TAILNET.server.address,
        }),
      ),
    ).toBeUndefined();
    // A header, even one without a usable address, means a proxy: judged, not local.
    expect(await s.auth.principal(viaCaddy(''))).toBeUndefined();
    expect(await s.auth.principal(viaCaddy('192.168.1.9'))).toBeUndefined();
    // Straight to the port from the tailnet or LAN: refused, whatever it claims.
    for (const peer of [
      TAILNET.phone.address,
      '192.168.86.53',
      '::ffff:100.101.102.103',
      undefined,
    ]) {
      expect([peer, await s.auth.principal(from(peer))]).toEqual([peer, undefined]);
      expect([
        peer,
        await s.auth.principal(from(peer, { 'x-forwarded-for': TAILNET.phone.address })),
      ]).toEqual([peer, undefined]);
    }
    expect(s.calls).toEqual([]);
  });

  it("admits a listed device and refuses one that isn't, logging each decision once", async () => {
    const s = await scheme([TAILNET.phone.id]);
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toEqual({
      scheme: 'tailscale',
      device: { id: TAILNET.phone.id, name: 'vern' },
      user: USER,
    });
    expect(await s.auth.principal(viaCaddy(TAILNET.tablet.address))).toEqual({
      refused: { id: TAILNET.tablet.id, name: 'ipad' },
    });
    // Over IPv6 too; a node without a login has no user.
    await writeFile(s.devicesPath, `${TAILNET.phone.id}\n${TAILNET.bare.id}\n`);
    expect(await s.auth.principal(viaCaddy(TAILNET.bare.address))).toEqual({
      scheme: 'tailscale',
      device: { id: TAILNET.bare.id, name: 'MacBook Air' },
    });
    // Again: the same decisions, nothing new logged.
    await s.auth.principal(viaCaddy(TAILNET.phone.address));
    await s.auth.principal(viaCaddy(TAILNET.tablet.address));
    expect(s.log.filter((line) => line.startsWith('[auth] tailscale device '))).toEqual([
      `[auth] tailscale device ${TAILNET.phone.id} (vern) allowed`,
      `[auth] tailscale device ${TAILNET.tablet.id} (ipad) not listed in ${s.devicesPath}: refused`,
      `[auth] tailscale device ${TAILNET.bare.id} (MacBook Air) allowed`,
    ]);
    expect(s.log.join('\n')).not.toContain(USER);
    // A list or a non-tailnet address: nothing to judge, and no whois.
    const before = s.calls.length;
    expect(await s.auth.principal(viaCaddy(`${TAILNET.phone.address}, 10.0.0.1`))).toBeUndefined();
    expect(await s.auth.principal(viaCaddy('192.168.1.9'))).toBeUndefined();
    expect(s.calls.length).toBe(before);
  });

  it("admits this server's own node unlisted, learning its id once from tailscale status", async () => {
    const s = await scheme([TAILNET.phone.id]);
    // A listed device needs no status call.
    await s.auth.principal(viaCaddy(TAILNET.phone.address));
    expect(s.calls.filter((call) => call[0] === 'status')).toEqual([]);
    const voyager = {
      scheme: 'tailscale',
      device: { id: TAILNET.self, name: 'voyager' },
      user: USER,
    };
    expect(await s.auth.principal(viaCaddy(TAILNET.server.address))).toEqual(voyager);
    // Long past the whois cache: whois again, but the node's id is kept.
    await s.tick(10 * 60_000);
    expect(await s.auth.principal(viaCaddy(TAILNET.server.address))).toEqual(voyager);
    expect(await s.auth.principal(viaCaddy(TAILNET.tablet.address))).toEqual({
      refused: { id: TAILNET.tablet.id, name: 'ipad' },
    });
    expect(s.calls.filter((call) => call[0] === 'status')).toEqual([['status', '--json']]);
    expect(s.calls.filter((call) => call[2] === TAILNET.server.address)).toHaveLength(2);
    expect(s.log).toContain(`[auth] tailscale this node (${TAILNET.self}) is always admitted`);
    expect(s.log).toContain(
      `[auth] tailscale device ${TAILNET.self} (voyager) is this server: allowed`,
    );
  });

  it("refuses this server's node while tailscale status fails, and asks again later", async () => {
    const fake = fakeTailscale();
    let up = false;
    const calls: string[][] = [];
    const exec: TailscaleExec = async (args, timeoutMs) => {
      calls.push([...args]);
      if (args[0] === 'status' && !up) throw new Error('tailscaled is not running');
      return fake.exec(args, timeoutMs);
    };
    const s = await scheme([], { exec });
    const refused = { refused: { id: TAILNET.self, name: 'voyager' } };
    expect(await s.auth.principal(viaCaddy(TAILNET.server.address))).toEqual(refused);
    expect(await s.auth.principal(viaCaddy(TAILNET.server.address))).toEqual(refused);
    expect(calls.filter((call) => call[0] === 'status')).toHaveLength(1);
    expect(s.log.filter((line) => line.includes('status failed'))).toEqual([
      "[auth] tailscale status failed, so this node isn't recognised: tailscaled is not running",
    ]);
    up = true;
    await s.tick(60_001);
    expect(await s.auth.principal(viaCaddy(TAILNET.server.address))).toMatchObject({
      scheme: 'tailscale',
      device: { id: TAILNET.self },
    });
    expect(calls.filter((call) => call[0] === 'status')).toHaveLength(2);
  });

  it('re-reads the devices file when it changes, so adding a device needs no restart', async () => {
    const s = await scheme([]);
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toEqual({
      refused: { id: TAILNET.phone.id, name: 'vern' },
    });
    await writeFile(s.devicesPath, `${TAILNET.phone.id} the phone\n`);
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toMatchObject({
      scheme: 'tailscale',
    });
    // Removed again, with the mtime moved on (a same-size rewrite in the same instant would look unchanged).
    await writeFile(s.devicesPath, `${TAILNET.tablet.id} the phone\n`);
    await utimes(s.devicesPath, new Date(), new Date(Date.now() + 5000));
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toEqual({
      refused: { id: TAILNET.phone.id, name: 'vern' },
    });
    expect(await s.auth.principal(viaCaddy(TAILNET.tablet.address))).toMatchObject({
      scheme: 'tailscale',
    });
    // Unchanged: not read again.
    await s.auth.principal(viaCaddy(TAILNET.tablet.address));
    expect(s.log.filter((line) => line.includes('devices file read'))).toEqual([
      '[auth] tailscale devices file read: 0 listed',
      '[auth] tailscale devices file read: 1 listed',
      '[auth] tailscale devices file read: 1 listed',
    ]);
  });

  it("stays on, admitting no listed device, while the devices file exists but can't be read", async () => {
    const s = await scheme(null);
    await mkdir(s.devicesPath);
    expect(await s.auth.enabled()).toBe(true);
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toEqual({
      refused: { id: TAILNET.phone.id, name: 'vern' },
    });
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toEqual({
      refused: { id: TAILNET.phone.id, name: 'vern' },
    });
    expect(s.log.filter((line) => line.includes("can't be read"))).toHaveLength(1);
    expect(s.log.find((line) => line.includes("can't be read"))).toMatch(
      new RegExp(
        `^\\[auth\\] tailscale devices file ${s.devicesPath} can't be read, so no device is allowed: `,
      ),
    );
    await rm(s.devicesPath, { recursive: true });
    await writeFile(s.devicesPath, `${TAILNET.phone.id}\n`);
    expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toMatchObject({
      scheme: 'tailscale',
    });
  });

  it('caches whois answers and misses per address for a minute', async () => {
    const s = await scheme([TAILNET.phone.id]);
    for (let k = 0; k < 5; k++)
      expect(await s.auth.principal(viaCaddy(TAILNET.phone.address))).toMatchObject({
        scheme: 'tailscale',
      });
    expect(s.calls).toEqual([['whois', '--json', TAILNET.phone.address]]);
    await s.tick(59_000);
    await s.auth.principal(viaCaddy(TAILNET.phone.address));
    expect(s.calls).toHaveLength(1);
    await s.tick(1_001);
    await s.auth.principal(viaCaddy(TAILNET.phone.address));
    expect(s.calls).toHaveLength(2);
    // A miss (whois knows no node there) is cached too, and logged once.
    const nowhere = '100.77.77.77';
    for (let k = 0; k < 3; k++) expect(await s.auth.principal(viaCaddy(nowhere))).toBeUndefined();
    expect(s.calls.filter((call) => call[2] === nowhere)).toHaveLength(1);
    const failures = () =>
      s.log.filter((line) => line.startsWith(`[auth] tailscale whois ${nowhere} failed`));
    expect(failures()).toHaveLength(1);
    await s.tick(60_001);
    await s.auth.principal(viaCaddy(nowhere));
    expect(s.calls.filter((call) => call[2] === nowhere)).toHaveLength(2);
    expect(failures()).toHaveLength(1);
    // Concurrent first requests share one whois.
    await Promise.all(
      Array.from({ length: 4 }, () => s.auth.principal(viaCaddy(TAILNET.tablet.address))),
    );
    expect(s.calls.filter((call) => call[2] === TAILNET.tablet.address)).toHaveLength(1);
  });

  it("fails closed when whois fails, answers junk, or doesn't answer in time", async () => {
    const whoisLines = (log: string[]) =>
      log.filter((line) => line.startsWith('[auth] tailscale whois '));

    const failing = await scheme([TAILNET.phone.id], {
      exec: async () => {
        throw new Error('tailscaled is not running');
      },
    });
    expect(await failing.auth.principal(viaCaddy(TAILNET.phone.address))).toBeUndefined();
    expect(whoisLines(failing.log)).toEqual([
      `[auth] tailscale whois ${TAILNET.phone.address} failed: tailscaled is not running`,
    ]);

    const junk = await scheme([TAILNET.phone.id], { exec: async () => '<html>' });
    expect(await junk.auth.principal(viaCaddy(TAILNET.phone.address))).toBeUndefined();
    expect(whoisLines(junk.log)).toHaveLength(1);

    let hangingRuns = 0;
    const hanging = await scheme([TAILNET.phone.id], {
      exec: () => {
        hangingRuns += 1;
        return new Promise(() => {});
      },
      timeoutMs: 40,
    });
    const started = Date.now();
    expect(await hanging.auth.principal(viaCaddy(TAILNET.phone.address))).toBeUndefined();
    expect(Date.now() - started).toBeGreaterThanOrEqual(35);
    expect(whoisLines(hanging.log)).toEqual([
      `[auth] tailscale whois ${TAILNET.phone.address} failed: no answer in 40 ms`,
    ]);
    // The failure is cached like a miss: the next request within the minute doesn't run (or wait on) whois again.
    // Counted rather than timed, so a busy machine can't fail it.
    expect(hangingRuns).toBe(1);
    expect(await hanging.auth.principal(viaCaddy(TAILNET.phone.address))).toBeUndefined();
    expect(hangingRuns).toBe(1);
  });
});

/**
 * A stand-in for the tailscale CLI: answers from the JSON files beside it, like
 * the real one fails for an address it doesn't know, and appends each call to
 * `calls`.
 */
const STAND_IN = `#!/bin/sh
dir=$(dirname "$0")
echo "$*" >> "$dir/calls"
case "$1" in
  status) exec cat "$dir/status.json" ;;
  whois)
    if [ -f "$dir/whois-$3.json" ]; then exec cat "$dir/whois-$3.json"; fi
    echo "no match for IP:port" >&2
    exit 1 ;;
esac
exit 2
`;

describe('the API', () => {
  let app: Express;
  let cli: string;
  // tests/setup.ts points this at a scratch path that doesn't exist: the scheme starts off.
  const devicesPath = devicesPathFrom();
  const lines: string[] = [];
  const authLines = () => lines.filter((line) => line.startsWith('[auth]'));
  const calls = async () => (await readFile(join(cli, 'calls'), 'utf8')).trim().split('\n');

  const OPEN = { scheme: 'open', device: null, user: null };
  const FRONTEND_PORT = 3456;
  const WEB = 'https://enchiridion.chsmc.tools';
  const EVIL = 'https://evil.example';
  const LISTED = "This device isn't on Enchiridion's list yet.";
  const UNKNOWN = "Enchiridion couldn't tell which device this is. Is Tailscale on?";
  /** A device's request as Caddy forwards it: the API's name as Host, and the device's address. */
  const caddy = (address: string) => ({ Host: API, 'X-Forwarded-For': address });
  const unauthorized = (message: string, device: { id: string; name: string } | null) => ({
    error: { code: 'unauthorized', message },
    message,
    device,
  });

  beforeAll(async () => {
    cli = await mkdtemp(join(tmpdir(), 'ench-tailscale-'));
    for (const node of [TAILNET.server, TAILNET.phone, TAILNET.tablet]) {
      await writeFile(join(cli, `whois-${node.address}.json`), whoisJson(node));
    }
    await writeFile(join(cli, 'status.json'), statusJson());
    await writeFile(join(cli, 'tailscale'), STAND_IN, { mode: 0o755 });
    process.env.ENCHIRIDION_TAILSCALE = join(cli, 'tailscale');
    process.env.FRONTEND_PORT = String(FRONTEND_PORT);
    vi.spyOn(console, 'log').mockImplementation((line: unknown) => void lines.push(String(line)));
    // Imported only now, so its auth reads the stand-in CLI from the environment.
    ({ app } = await import('@api/app'));
  });

  afterAll(async () => {
    vi.restoreAllMocks();
    await rm(devicesPath, { force: true });
    await rm(cli, { recursive: true, force: true });
  });

  it('is open, and says so, while there is no devices file', async () => {
    const info = await request(app).get('/info');
    expect([info.status, info.body]).toEqual([200, { name: 'enchiridion', auth: [] }]);
    expect((await request(app).get('/me')).body).toEqual(OPEN);
    // With the scheme off, a forwarded address means nothing.
    expect(
      (await request(app).get('/me').set('X-Forwarded-For', TAILNET.tablet.address)).body,
    ).toEqual(OPEN);
    expect((await request(app).post('/records').send({ limit: 1 })).status).toBe(200);
    // Off, any page may call it, exactly as before the scheme existed.
    const foreign = await request(app).get('/me').set('Origin', EVIL);
    expect([foreign.status, foreign.headers['access-control-allow-origin']]).toEqual([200, '*']);
    expect(authLines()).toEqual([`[auth] tailscale off: no devices file at ${devicesPath}`]);
    await expect(calls()).rejects.toThrow(); // no CLI ran
  });

  it('refuses to update a record that no longer exists, rather than inserting a bare one', async () => {
    const created = await request(app).put('/record').send({
      slug: 'deleted-elsewhere',
      title: 'Deleted elsewhere',
      url: 'https://example.com/a',
    });
    expect(created.status).toBe(200);
    const { id } = created.body as { id: number };
    // An update sends only what it changes; the rest is kept.
    const curated = await request(app)
      .put('/record')
      .send({ id, slug: 'deleted-elsewhere', isCurated: true });
    expect([curated.status, curated.body.title, curated.body.isCurated]).toEqual([
      200,
      'Deleted elsewhere',
      true,
    ]);
    expect((await request(app).delete(`/record/${id}`)).status).toBe(200);

    const stale = await request(app)
      .put('/record')
      .send({ id, slug: 'deleted-elsewhere', isCurated: false });
    expect([stale.status, stale.body.error?.code]).toEqual([404, 'not_found']);
    expect(stale.body.message).toMatch(/doesn't exist/);
    expect((await request(app).get(`/record/${id}`)).status).toBe(404);
    const index = await request(app).post('/records').send({ limit: 100_000 });
    expect((index.body as { slug: string }[]).map((row) => row.slug)).not.toContain(
      'deleted-elsewhere',
    );
    // A create (no id) still goes through, and so does an update of a record that exists.
    const again = await request(app)
      .put('/record')
      .send({ slug: 'deleted-elsewhere', title: 'Back' });
    expect(again.status).toBe(200);
    const renamed = await request(app)
      .put('/record')
      .send({ id: again.body.id, slug: 'deleted-elsewhere', title: 'Back again' });
    expect([renamed.status, renamed.body.title]).toEqual([200, 'Back again']);
  });

  it('turns on when the devices file appears, admitting listed devices, this server and local processes', async () => {
    await writeFile(
      devicesPath,
      `# Tailscale nodes allowed to use Enchiridion\n${TAILNET.phone.id} vern\n`,
    );
    expect((await request(app).get('/info')).body).toEqual({
      name: 'enchiridion',
      auth: ['tailscale'],
    });
    expect(authLines()).toContain(`[auth] tailscale on: ${devicesPath}`);

    const local = await request(app).get('/me');
    expect([local.status, local.body]).toEqual([
      200,
      { scheme: 'local', device: null, user: null },
    ]);
    expect(local.headers['cache-control']).toBe('no-store');

    const phone = await request(app).get('/me').set(caddy(TAILNET.phone.address));
    expect([phone.status, phone.body]).toEqual([
      200,
      { scheme: 'tailscale', device: { id: TAILNET.phone.id, name: 'vern' }, user: USER },
    ]);
    const voyager = await request(app).get('/me').set(caddy(TAILNET.server.address));
    expect([voyager.status, voyager.body]).toEqual([
      200,
      { scheme: 'tailscale', device: { id: TAILNET.self, name: 'voyager' }, user: USER },
    ]);
    const list = await request(app)
      .post('/records')
      .set(caddy(TAILNET.phone.address))
      .send({ limit: 1 });
    expect(list.status).toBe(200);

    // One whois per address (cached), and status once, for the server's own node.
    expect(
      (await calls()).filter((call) => call === `whois --json ${TAILNET.phone.address}`),
    ).toHaveLength(1);
    expect((await calls()).filter((call) => call === 'status --json')).toHaveLength(1);
  });

  it('refuses everyone else on every path but /info, naming the device when it can', async () => {
    const refused = await request(app).get('/me').set(caddy(TAILNET.tablet.address));
    expect(refused.status).toBe(401);
    expect(refused.headers['www-authenticate']).toBe('Tailscale realm="enchiridion"');
    expect(refused.headers['cache-control']).toBe('no-store');
    expect(refused.body).toEqual(unauthorized(LISTED, { id: TAILNET.tablet.id, name: 'ipad' }));

    // No device to name: whois doesn't know the address, it isn't a tailnet address, or it's a list.
    for (const forwarded of ['100.77.77.77', '192.168.1.9', `${TAILNET.phone.address}, 10.0.0.1`]) {
      const res = await request(app).get('/record/1').set(caddy(forwarded));
      expect([forwarded, res.status, res.headers['www-authenticate'], res.body]).toEqual([
        forwarded,
        401,
        'Tailscale realm="enchiridion"',
        unauthorized(UNKNOWN, null),
      ]);
    }

    // Static files and unknown paths are gated too; only /info is open.
    for (const path of [
      '/uploads/nothing.png',
      '/archives/nothing/index.html',
      '/nope',
      '/search?q=x',
    ]) {
      const res = await request(app).get(path).set(caddy(TAILNET.tablet.address));
      expect([path, res.status]).toEqual([path, 401]);
    }
    const create = await request(app)
      .put('/record')
      .set(caddy(TAILNET.tablet.address))
      .send({ slug: 'refused', title: 'Refused' });
    expect(create.status).toBe(401);
    const info = await request(app).get('/info').set(caddy(TAILNET.tablet.address));
    expect([info.status, info.body]).toEqual([200, { name: 'enchiridion', auth: ['tailscale'] }]);
  });

  it('answers preflights and puts CORS headers on a 401, so the web app can read it', async () => {
    const preflight = await request(app)
      .options('/records')
      .set('Origin', WEB)
      .set('Access-Control-Request-Method', 'POST')
      .set('Access-Control-Request-Headers', 'content-type')
      .set(caddy(TAILNET.tablet.address));
    expect([preflight.status, preflight.headers['access-control-allow-origin']]).toEqual([
      204,
      WEB,
    ]);
    expect(preflight.headers.vary).toMatch(/Origin/);
    const refused = await request(app)
      .post('/records')
      .set('Origin', WEB)
      .set(caddy(TAILNET.tablet.address))
      .send({ limit: 1 });
    expect([refused.status, refused.headers['access-control-allow-origin']]).toEqual([401, WEB]);
    expect(refused.body.message).toBe(LISTED);
    // The Vite dev server on this machine is the web app too.
    const dev = `http://localhost:${FRONTEND_PORT}`;
    const local = await request(app).get('/me').set('Origin', dev).set('Host', 'localhost:4321');
    expect([local.status, local.body.scheme, local.headers['access-control-allow-origin']]).toEqual(
      [200, 'local', dev],
    );
    // But not a page at localhost:3456 on a listed device (another project's dev server, say),
    // calling the API through Caddy: localhost there is that device, not this server's web app.
    for (const attempt of [
      request(app).get('/me').set('Origin', dev).set(caddy(TAILNET.phone.address)),
      request(app)
        .options('/record/1')
        .set('Origin', `http://[::1]:${FRONTEND_PORT}`)
        .set('Access-Control-Request-Method', 'DELETE')
        .set(caddy(TAILNET.phone.address)),
    ]) {
      const res = await attempt;
      expect([
        res.status,
        res.body.error?.code,
        res.headers['access-control-allow-origin'],
      ]).toEqual([403, 'forbidden_origin', undefined]);
    }
  });

  it("refuses every other site's page, so a page can't use the API as the browser's device", async () => {
    const forbidden = {
      error: { code: 'forbidden_origin', message: FORBIDDEN_ORIGIN },
      message: FORBIDDEN_ORIGIN,
    };
    const attempts = [
      // A page in Safari on the listed phone, reading and writing through Caddy as that device.
      request(app).get('/me').set('Origin', EVIL).set(caddy(TAILNET.phone.address)),
      request(app)
        .post('/records')
        .set('Origin', EVIL)
        .set(caddy(TAILNET.phone.address))
        .send({ limit: 1 }),
      request(app)
        .options('/record/1')
        .set('Origin', EVIL)
        .set('Access-Control-Request-Method', 'DELETE')
        .set(caddy(TAILNET.phone.address)),
      // A page in a browser on voyager, straight to the port as a local process; a form post needs no preflight.
      request(app).delete('/record/1').set('Origin', EVIL),
      request(app).post('/records').set('Origin', EVIL).type('form').send({ limit: '1' }),
      // A sandboxed frame, and a lookalike of the web app's origin.
      request(app).get('/me').set('Origin', 'null'),
      request(app).get('/me').set('Origin', `${WEB}.evil.example`),
      request(app).get('/info').set('Origin', EVIL),
    ];
    for (const attempt of attempts) {
      const res = await attempt;
      expect([res.status, res.body, res.headers['access-control-allow-origin']]).toEqual([
        403,
        forbidden,
        undefined,
      ]);
    }
    // Rebinding a name to 127.0.0.1 makes a same-origin request, which carries no Origin: its Host gives it away.
    const rebound = await request(app).get('/record/1').set('Host', 'rebind.evil.example:4321');
    expect([rebound.status, rebound.body]).toEqual([401, unauthorized(UNKNOWN, null)]);
    // Page script may set X-Forwarded-For, but not Host: even this server's own address is ignored,
    // no whois runs, and so the 401 can't tell the page which addresses are tailnet nodes.
    const before = (await calls()).length;
    for (const address of [TAILNET.server.address, TAILNET.phone.address, TAILNET.tablet.address]) {
      const forged = await request(app)
        .get('/search?q=x')
        .set('Host', 'rebind.evil.example:4321')
        .set('X-Forwarded-For', address);
      expect([address, forged.status, forged.body]).toEqual([
        address,
        401,
        unauthorized(UNKNOWN, null),
      ]);
    }
    expect((await calls()).length).toBe(before);
  });

  it("loads an archived page's own fonts, sandboxes the page, and refuses the page's fetch() calls", async () => {
    const { archiveRoot } = await import('@integrations/archive');
    await mkdir(join(archiveRoot(), 'fonts-test', 'assets'), { recursive: true });
    await writeFile(join(archiveRoot(), 'fonts-test', 'assets', 'f.woff2'), 'wOF2');
    await writeFile(join(archiveRoot(), 'fonts-test', 'index.html'), '<!doctype html><p>Kept</p>');
    const font = '/archives/fonts-test/assets/f.woff2';
    // From the sandboxed frame in the web app, and the sandboxed archive opened in a tab: Origin null.
    // A browser that ignores the sandbox sends the API's own origin. Locally, or as a listed device.
    for (const origin of ['null', `https://${API}`]) {
      for (const headers of [{}, caddy(TAILNET.phone.address)]) {
        const res = await request(app)
          .get(font)
          .set(headers)
          .set('Origin', origin)
          .set('Sec-Fetch-Dest', 'font');
        expect([origin, headers, res.status, res.headers['access-control-allow-origin']]).toEqual([
          origin,
          headers,
          200,
          origin,
        ]);
      }
    }
    // The device check still applies.
    const unlisted = await request(app)
      .get(font)
      .set(caddy(TAILNET.tablet.address))
      .set('Origin', 'null')
      .set('Sec-Fetch-Dest', 'font');
    expect(unlisted.status).toBe(401);
    // The page's own fetch() (dest `empty`), a request that says nothing, and an asset
    // destination anywhere but /archives: refused like any other site's page.
    const refusals = [
      request(app).get(font).set('Origin', 'null').set('Sec-Fetch-Dest', 'empty'),
      request(app).get(font).set('Origin', 'null'),
      request(app).get('/archives/fonts-test/index.html').set('Origin', 'null'),
      request(app).get('/me').set('Origin', 'null').set('Sec-Fetch-Dest', 'script'),
      request(app)
        .get('/search?q=x')
        .set('Origin', `https://${API}`)
        .set('Sec-Fetch-Dest', 'empty'),
    ];
    for (const refusal of refusals) {
      const res = await refusal;
      expect([res.status, res.headers['access-control-allow-origin']]).toEqual([403, undefined]);
    }
    // The page itself (and anything else under /archives) is served sandboxed: no script in it runs as the API's origin.
    for (const headers of [{}, caddy(TAILNET.phone.address)]) {
      const page = await request(app).get('/archives/fonts-test/index.html').set(headers);
      expect([page.status, page.headers['content-security-policy']]).toEqual([200, ARCHIVE_CSP]);
    }
    expect((await request(app).get('/me')).headers['content-security-policy']).toBeUndefined();
  });

  it("refuses a peer that isn't loopback, whatever it sends", async () => {
    /** The app as reached straight on its port from `peer`, not through Caddy. */
    const direct = (peer: string) => (req: IncomingMessage, res: ServerResponse) => {
      Object.defineProperty(req.socket, 'remoteAddress', { value: peer, configurable: true });
      app(req, res);
    };
    const before = (await calls()).length;
    for (const peer of [TAILNET.phone.address, '192.168.86.53']) {
      for (const headers of [{}, caddy(TAILNET.phone.address)]) {
        const res = await request(direct(peer)).get('/me').set(headers);
        expect([peer, headers, res.status, res.body]).toEqual([
          peer,
          headers,
          401,
          unauthorized(UNKNOWN, null),
        ]);
      }
    }
    expect((await calls()).length).toBe(before);
  });

  it('is open again once the devices file has stayed deleted for a moment', async () => {
    await rm(devicesPath);
    vi.useFakeTimers({ toFake: ['Date'] });
    try {
      // Just gone, as when an editor replaces it: still on. Checks a quarter of the grace
      // apart (as its own re-checks are) find it gone until the grace has passed.
      const info = { name: 'enchiridion', auth: ['tailscale'] };
      expect((await request(app).get('/info')).body).toEqual(info);
      for (let k = 0; k < 3; k++) {
        vi.setSystemTime(Date.now() + MISSING_GRACE_MS / 4);
        expect((await request(app).get('/info')).body).toEqual(info);
      }
      vi.setSystemTime(Date.now() + MISSING_GRACE_MS / 4 - 1);
      expect((await request(app).get('/info')).body).toEqual(info);
      vi.setSystemTime(Date.now() + 1);
      expect((await request(app).get('/info')).body).toEqual({ name: 'enchiridion', auth: [] });
    } finally {
      vi.useRealTimers();
    }
    const tablet = await request(app).get('/me').set(caddy(TAILNET.tablet.address));
    expect([tablet.status, tablet.body]).toEqual([200, OPEN]);
    const foreign = await request(app).get('/me').set('Origin', EVIL);
    expect([foreign.status, foreign.headers['access-control-allow-origin']]).toEqual([200, '*']);
    // Archives as they always were: not sandboxed, and readable from anywhere.
    const page = await request(app).get('/archives/fonts-test/index.html');
    expect([page.status, page.headers['content-security-policy']]).toEqual([200, undefined]);
    const font = await request(app)
      .get('/archives/fonts-test/assets/f.woff2')
      .set('Origin', 'null')
      .set('Sec-Fetch-Dest', 'empty');
    expect([font.status, font.headers['access-control-allow-origin']]).toEqual([200, '*']);
    expect(authLines().filter((line) => /^\[auth\] tailscale (on|off):/.test(line))).toEqual([
      `[auth] tailscale off: no devices file at ${devicesPath}`,
      `[auth] tailscale on: ${devicesPath}`,
      `[auth] tailscale off: no devices file at ${devicesPath}`,
    ]);
  });
});
