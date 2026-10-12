/**
 * Who may use the API: Tailscale identity, ported from familiar's scheme
 * (~/Repositories/familiar/src/server/auth.ts). Caddy proxies
 * enchiridion-api.chsmc.tools to this server from loopback and overwrites
 * X-Forwarded-For with the tailnet peer's address; `tailscale whois` names that
 * node, and a devices file lists the nodes admitted.
 *
 * Where it deliberately differs from familiar:
 * - Off, with the API open as it always was, unless the devices file exists.
 *   Creating or deleting the file switches the scheme without a restart (a
 *   file that has been on goes off only once it stays missing for a moment,
 *   so an editor replacing it never opens the API).
 * - Loopback with no X-Forwarded-For is a local process (Caddy always adds the
 *   header), admitted as `local` when its Host names this machine: it can read
 *   the database anyway.
 * - X-Forwarded-For is read only when Host is the API's public name, which
 *   Caddy passes through. A page in a browser on this machine whose name was
 *   rebound to 127.0.0.1 can set X-Forwarded-For itself, but its Host names its
 *   own site, so it passes neither as local nor as a forwarded device.
 * - This server's own node is admitted: the web app, the iOS Simulator and
 *   agents on voyager reach the API through Caddy as that node.
 * - No bearer token, and a device is named by its MagicDNS label first, since
 *   iPhones report the hostname "localhost".
 * - Where familiar refuses any request with an Origin, this one refuses only
 *   origins other than the web app's (`originGate`): admission goes by where a
 *   request comes from, so without it any page open in an admitted browser
 *   could use the API as that device. Archived pages' own fonts, images,
 *   styles and scripts are let through (`isArchiveAsset`), and archives are
 *   served sandboxed (`ARCHIVE_CSP`), so their scripts never run as the API.
 */
import { execFile } from 'node:child_process';
import { readFile, stat } from 'node:fs/promises';
import type { IncomingHttpHeaders } from 'node:http';
import { isIPv4, isIPv6 } from 'node:net';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type { CorsOptionsDelegate } from 'cors';
import type { Request, RequestHandler } from 'express';

/**
 * How a request was admitted: `tailscale` (a listed device, or this server's
 * own node), `local` (loopback without a proxy), or `open` (the scheme is off).
 */
export type AuthScheme = 'tailscale' | 'local' | 'open';

/** A tailnet node: its stable id (`Node.StableID`) and a name for people. */
export interface Device {
  id: string;
  name: string;
}

/** Who a request is from. `device` and `user` come with the tailscale scheme only. */
export interface Principal {
  scheme: AuthScheme;
  device?: Device;
  user?: string;
}

/** A node the scheme resolved but doesn't admit, so the 401 can name it. */
export interface Refusal {
  refused: Device;
}

/** What the scheme says of a request: who it is from, a device it refuses, or nothing it can tell. */
export type Verdict = Principal | Refusal | undefined;

export const isPrincipal = (verdict: Verdict): verdict is Principal =>
  verdict !== undefined && 'scheme' in verdict;

/** What the scheme reads of a request: the TCP peer and the headers. An Express request is one. */
export interface PeerRequest {
  socket?: { remoteAddress?: string | undefined } | null;
  headers: IncomingHttpHeaders;
}

export const WHOIS_TIMEOUT_MS = 2000;
export const WHOIS_CACHE_MS = 60_000;
/** `tailscale status` describes the whole tailnet, so it can be slower than a whois. */
export const STATUS_TIMEOUT_MS = 10_000;
/**
 * How long a devices file that was there must stay missing before the scheme
 * turns off: an editor that saves by renaming the old file away and writing a
 * new one (Vim's default) leaves no file for a moment, which must not open the
 * API. "Stayed missing" means every check over that time found it missing, with
 * none more than half of it apart: a longer gap could hide the file coming back
 * and going again (a second save), so the grace starts over. While it is
 * missing the file is checked every quarter of the grace without waiting for a
 * request, so a real deletion still turns the scheme off when requests are
 * sparse, and a save is seen to end even with no request.
 */
export const MISSING_GRACE_MS = 2000;

export const UNAUTHORIZED_LISTED = "This device isn't on Enchiridion's list yet.";
export const UNAUTHORIZED_UNKNOWN =
  "Enchiridion couldn't tell which device this is. Is Tailscale on?";
export const CHALLENGE = 'Tailscale realm="enchiridion"';
export const FORBIDDEN_ORIGIN = 'Enchiridion only answers pages from its own web app.';

const messageOf = (error: unknown) => (error instanceof Error ? error.message : String(error));

// ─── The tailscale CLI ──────────────────────────────────────────────────────

/** Runs the tailscale CLI with `args` and resolves with its stdout; rejects when it fails or `timeoutMs` passes. */
export type TailscaleExec = (args: readonly string[], timeoutMs: number) => Promise<string>;

/** The real CLI. Never through a shell, so a forwarded address is always one argument. */
export function tailscaleExec(
  bin = process.env.ENCHIRIDION_TAILSCALE || 'tailscale',
): TailscaleExec {
  return (args, timeoutMs) =>
    new Promise((resolve, reject) => {
      execFile(
        bin,
        args,
        { timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024, windowsHide: true },
        (error, stdout) => (error === null ? resolve(stdout) : reject(error)),
      );
    });
}

/** A whois answer: the node, and the tailnet login it belongs to. */
export interface WhoisResult {
  device: Device;
  user: string | null;
}

/**
 * The fields of `tailscale whois --json` the scheme reads (tailscale 1.102):
 * Node.StableID, Node.Name ("vern.tail9000e.ts.net."), Node.Hostinfo.Hostname
 * and UserProfile.LoginName. The name is the MagicDNS name's first label, else
 * the hostname, else the id. Throws when the JSON isn't a node.
 */
export function parseWhois(json: string): WhoisResult {
  const data = JSON.parse(json) as {
    Node?: { StableID?: unknown; Name?: unknown; Hostinfo?: { Hostname?: unknown } };
    UserProfile?: { LoginName?: unknown };
  } | null;
  const node = data?.Node;
  const id = node?.StableID;
  if (typeof id !== 'string' || id === '') throw new Error('no Node.StableID in the whois answer');
  const dnsName = node?.Name;
  const label = typeof dnsName === 'string' ? (dnsName.trim().split('.')[0] ?? '') : '';
  const hostname = node?.Hostinfo?.Hostname;
  const host = typeof hostname === 'string' ? hostname.trim() : '';
  const login = data?.UserProfile?.LoginName;
  return {
    device: { id, name: label || host || id },
    user: typeof login === 'string' && login !== '' ? login : null,
  };
}

/** Self.ID from `tailscale status --json`: this server's own node, which is always admitted. */
export function parseSelf(json: string): string {
  const id = (JSON.parse(json) as { Self?: { ID?: unknown } } | null)?.Self?.ID;
  if (typeof id !== 'string' || id === '') throw new Error('no Self.ID in the status answer');
  return id;
}

// ─── The devices file ───────────────────────────────────────────────────────

/** `ENCHIRIDION_DEVICES` (a leading `~` is expanded), else `~/.enchiridion/devices`. */
export function devicesPathFrom(env: NodeJS.ProcessEnv = process.env): string {
  const given = env.ENCHIRIDION_DEVICES?.trim();
  if (!given) return join(homedir(), '.enchiridion', 'devices');
  return given.replace(/^~(?=$|\/)/, homedir());
}

/**
 * The allowlist: one stable id per line, optionally followed by whitespace and
 * a name for people; `#` starts a comment; blank lines are skipped. The ids,
 * each with its name ("" when none).
 */
export function parseDevices(text: string): Map<string, string> {
  const devices = new Map<string, string>();
  for (const raw of text.split('\n')) {
    const line = raw.replace(/#.*$/, '').trim();
    if (line === '') continue;
    const [id = '', ...rest] = line.split(/\s+/);
    devices.set(id, rest.join(' '));
  }
  return devices;
}

// ─── Which address is judged ────────────────────────────────────────────────

/** The TCP peer is this machine: on voyager, Caddy or a local process. */
export const isLoopback = (address: string | undefined): boolean =>
  address !== undefined &&
  (/^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(address) ||
    address === '::1' ||
    /^::ffff:127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/i.test(address));

/** A tailnet address: IPv4 in 100.64.0.0/10 or IPv6 in fd7a:115c:a1e0::/48. */
export function isTailnetAddress(address: string): boolean {
  if (isIPv4(address)) {
    const [a, b = -1] = address.split('.').map(Number);
    return a === 100 && b >= 64 && b <= 127;
  }
  return isIPv6(address) && /^fd7a:115c:a1e0:/i.test(address);
}

/** The API's public name, the Host that Caddy passes through when it proxies a device's request. */
export const DEFAULT_API_HOST = 'enchiridion-api.chsmc.tools';

/** A Host header's name: lowercased, without its port. An IPv6 literal keeps its brackets. */
export function hostName(host: string): string {
  const value = host.trim().toLowerCase();
  return value.startsWith('[')
    ? value.slice(0, value.indexOf(']') + 1)
    : value.replace(/:\d*$/, '');
}

/** `ENCHIRIDION_API_HOST` (a name, any port dropped), else `DEFAULT_API_HOST`. */
export function apiHostFrom(env: NodeJS.ProcessEnv = process.env): string {
  const given = env.ENCHIRIDION_API_HOST?.trim();
  return given ? hostName(given) : DEFAULT_API_HOST;
}

/**
 * The address the scheme judges: X-Forwarded-For when the peer is loopback, the
 * Host is `apiHost` (Caddy passes the client's through), and the header holds
 * exactly one tailnet address (Caddy sets it to the peer's; a list means a proxy
 * chain the scheme doesn't know). Else undefined. Anything a non-loopback peer
 * sends is its own claim, so it is never read. Nor is the header of a request
 * to any other name: a page in a browser on this machine whose name was rebound
 * to 127.0.0.1 can set X-Forwarded-For, but not Host, which names its own site.
 */
export function forwardedTailnetAddress(req: PeerRequest, apiHost: string): string | undefined {
  if (!isLoopback(req.socket?.remoteAddress)) return undefined;
  const { host } = req.headers;
  if (host === undefined || hostName(host) !== hostName(apiHost)) return undefined;
  const header = req.headers['x-forwarded-for'];
  if (typeof header !== 'string') return undefined;
  const address = header.trim();
  if (address === '' || address.includes(',') || !isTailnetAddress(address)) return undefined;
  return address;
}

/**
 * A Host header that names this machine: `localhost`, a 127/8 address or
 * `[::1]`, with or without a port. A browser sends the page's own host name, so
 * a page whose name an attacker rebinds to 127.0.0.1 never passes.
 */
export function isLoopbackHost(host: string): boolean {
  const name = hostName(host);
  return name === 'localhost' || name === '[::1]' || /^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(name);
}

/**
 * A local process: a loopback peer with no X-Forwarded-For (Caddy always adds
 * one) whose Host, when it sends one, names this machine. No browser leaves
 * Host out.
 */
export function isLocalRequest(req: PeerRequest): boolean {
  if (!isLoopback(req.socket?.remoteAddress) || req.headers['x-forwarded-for'] !== undefined) {
    return false;
  }
  const { host } = req.headers;
  return host === undefined || isLoopbackHost(host);
}

// ─── Which pages may call it ────────────────────────────────────────────────

/** The production web app's origin. */
export const WEB_ORIGIN = 'https://enchiridion.chsmc.tools';

/**
 * The web app's origins, the only pages a browser may call the API from while
 * the scheme is on (`isWebOrigin`).
 */
export interface WebOrigins {
  /** The production web app's (`WEB_ORIGIN`): accepted on any request. */
  site: string;
  /**
   * The Vite dev server's, on loopback at `FRONTEND_PORT`: accepted only from a
   * local process (`isLocalRequest`). `localhost` names whichever machine the
   * browser runs on, so through Caddy it would be a page on some listed device's
   * own port; the dev web app always calls its own machine's API on its port.
   */
  dev: ReadonlySet<string>;
}

/** The production web app, and the Vite dev server on loopback at `FRONTEND_PORT` (when it is a port). */
export function webOriginsFrom(env: NodeJS.ProcessEnv = process.env): WebOrigins {
  const dev = new Set<string>();
  const port = env.FRONTEND_PORT?.trim();
  if (port !== undefined && /^\d+$/.test(port)) {
    for (const host of ['localhost', '127.0.0.1', '[::1]']) dev.add(`http://${host}:${port}`);
  }
  return { site: WEB_ORIGIN, dev };
}

/** Whether `origin` is the web app's own, for this request: the site's always, a dev server's only locally. */
export const isWebOrigin = (origins: WebOrigins, origin: string, req: PeerRequest): boolean =>
  origin === origins.site || (origins.dev.has(origin) && isLocalRequest(req));

/** The `Sec-Fetch-Dest` values of what a page's own markup and CSS load: fonts, images, style sheets, scripts, media. */
const ASSET_DESTINATIONS: ReadonlySet<string> = new Set([
  'font',
  'image',
  'style',
  'script',
  'audio',
  'video',
  'track',
]);

/**
 * A file under `/archives` loaded by a page's markup or CSS: a GET or HEAD whose
 * `Sec-Fetch-Dest` is a font, image, style sheet, script or media. Browsers
 * load @font-face fonts, module scripts, CSS masks and `crossorigin` elements in
 * CORS mode, so an archived page's own assets carry an Origin: `null` from the
 * sandboxed frame the web app shows it in, or from `ARCHIVE_CSP` when it is
 * opened in a tab. Page script can't set `Sec-Fetch-*`, and a fetch() always
 * says `empty`, so this never lets a page read API data, nor an archive's HTML.
 */
export function isArchiveAsset(req: Pick<Request, 'method' | 'path' | 'headers'>): boolean {
  const dest = req.headers['sec-fetch-dest'];
  return (
    (req.method === 'GET' || req.method === 'HEAD') &&
    req.path.startsWith('/archives/') &&
    typeof dest === 'string' &&
    ASSET_DESTINATIONS.has(dest)
  );
}

/**
 * Archives are other sites' pages, some with their scripts kept, served from the
 * API's own origin. While the scheme is on they are served with this policy:
 * opened in a tab, an archive gets an opaque origin, so its scripts can't call
 * the API as the browser's device (their requests carry `Origin: null`, which
 * the origin gate refuses). Links, popups and forms still work.
 */
export const ARCHIVE_CSP =
  'sandbox allow-scripts allow-popups allow-popups-to-escape-sandbox allow-forms';

/**
 * While the scheme is on, refuses (403) a request whose Origin isn't the web
 * app's (`isWebOrigin`), before CORS and auth. The scheme admits a request by where it
 * comes from, and a page on any site that a listed device's browser (or one on
 * voyager) opens comes from there too: without this it could read and write
 * the knowledge base as that device. Covers preflights and simple requests
 * (form posts) alike, so it stops cross-site reads and writes. The app, curl
 * and scripts send no Origin. An archived page's own assets (`isArchiveAsset`)
 * go on to the device check. While off, the API stays as open as it was.
 */
export function originGate(
  webOrigins: WebOrigins,
  enabled: () => Promise<boolean>,
): RequestHandler {
  return async (req, res, next) => {
    const { origin } = req.headers;
    if (
      origin === undefined ||
      isWebOrigin(webOrigins, origin, req) ||
      isArchiveAsset(req) ||
      !(await enabled())
    ) {
      next();
      return;
    }
    res
      .status(403)
      .set('Cache-Control', 'no-store')
      .json({
        error: { code: 'forbidden_origin', message: FORBIDDEN_ORIGIN },
        message: FORBIDDEN_ORIGIN,
      });
  };
}

/**
 * cors()'s options, per request: while the scheme is on, the web app's own
 * origins only (`isWebOrigin`; echoed, so the web app can read a 401), and
 * whatever origin an archived page's own asset comes with (`null` from its
 * sandbox), so its fonts load; while off, `*`, as it always was.
 */
export function corsOptions(
  webOrigins: WebOrigins,
  enabled: () => Promise<boolean>,
): CorsOptionsDelegate<Request> {
  return (req, callback) => {
    enabled().then(
      (on) => {
        const { origin } = req.headers;
        const allowed =
          isArchiveAsset(req) || (origin !== undefined && isWebOrigin(webOrigins, origin, req));
        callback(null, { origin: on ? allowed : '*' });
      },
      (error: unknown) => callback(error instanceof Error ? error : new Error(String(error))),
    );
  };
}

// ─── The scheme ─────────────────────────────────────────────────────────────

export interface TailscaleAuthOptions {
  /** The allowlist. Its existence switches the scheme on; re-read when its mtime or size changes. */
  devicesPath: string;
  exec: TailscaleExec;
  log: (line: string) => void;
  /** The clock the caches and the missing-file grace read. */
  now?: () => number;
  /** How long a devices file that was there must stay missing before the scheme turns off (`MISSING_GRACE_MS`). */
  missingGraceMs?: number;
  /** Runs `run` after `ms`: the re-checks of a missing devices file. An unref'd timer by default. */
  schedule?: (run: () => Promise<unknown>, ms: number) => void;
  /** How long a whois may take: past it, the request isn't authenticated. */
  timeoutMs?: number;
  /** How long `tailscale status` may take when learning this server's own node. */
  statusTimeoutMs?: number;
  /** How long an address's whois answer, or its failure, is kept. */
  cacheMs?: number;
  /** The Host a request through Caddy names (`DEFAULT_API_HOST` when left out): X-Forwarded-For is read only then. */
  apiHost?: string;
}

export interface TailscaleAuth {
  /**
   * Admits a request or answers 401 (with `WWW-Authenticate` and a body that
   * names the device when it can). An admitted request's principal is on
   * `res.locals.principal`.
   */
  middleware: RequestHandler;
  /** Judges a request: `{scheme: 'open'}` while the scheme is off. */
  principal(req: PeerRequest): Promise<Verdict>;
  /** Whether the scheme is on, i.e. the devices file exists (or hasn't yet stayed missing for `missingGraceMs`). */
  enabled(): Promise<boolean>;
}

type DevicesState = { on: false } | { on: true; allowed: ReadonlyMap<string, string> };

/** Missing, as opposed to unreadable: only a missing file turns the scheme off. */
const isMissing = (error: unknown) => {
  const code = (error as NodeJS.ErrnoException | null)?.code;
  return code === 'ENOENT' || code === 'ENOTDIR';
};

async function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const late = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`no answer in ${ms} ms`)), ms);
  });
  try {
    return await Promise.race([promise, late]);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * The tailscale scheme over `devicesPath`. Whois answers are cached per address
 * for a minute, misses and failures too, and a whois that fails or times out
 * isn't authenticated (closed), logged once per address. Each device's decision
 * is logged when first seen or when it changes; never the login.
 */
export function createTailscaleAuth(options: TailscaleAuthOptions): TailscaleAuth {
  const {
    devicesPath: path,
    exec,
    log,
    now = () => Date.now(),
    timeoutMs = WHOIS_TIMEOUT_MS,
    statusTimeoutMs = STATUS_TIMEOUT_MS,
    cacheMs = WHOIS_CACHE_MS,
    missingGraceMs = MISSING_GRACE_MS,
    schedule = (run, ms) => void setTimeout(() => void run(), ms).unref(),
    apiHost = DEFAULT_API_HOST,
  } = options;

  // ── The devices file: its existence is the switch, its contents the allowlist.
  let state: DevicesState | undefined; // undefined until first read, so startup always logs
  let stamp: string | undefined; // `mtime:size` as last read, 'missing', or undefined to read again
  let unreadable = false; // whether "can't be read" has been logged
  // While an on scheme finds the file missing: the first check of this run of
  // missing checks, and the latest. Cleared by any check that finds it there.
  let missing: { since: number; last: number } | undefined;
  let recheckDue = false; // whether a re-check of the missing file is scheduled
  const recheckMs = missingGraceMs / 4;
  const maxGapMs = missingGraceMs / 2;
  let reading: Promise<DevicesState> | undefined;

  const settle = (next: DevicesState): DevicesState => {
    if (state?.on !== next.on) {
      log(
        next.on
          ? `[auth] tailscale on: ${path}`
          : `[auth] tailscale off: no devices file at ${path}`,
      );
    }
    state = next;
    return next;
  };

  const read = async (): Promise<DevicesState> => {
    let text: string;
    try {
      const s = await stat(path);
      const next = `${s.mtimeMs}:${s.size}`;
      if (next === stamp && state !== undefined) return state;
      text = await readFile(path, 'utf8');
      stamp = next;
    } catch (error) {
      if (isMissing(error)) {
        stamp = 'missing';
        unreadable = false;
        // Missing from a scheme that was on: being replaced, or deleted. Keep the
        // last allowlist until it has stayed missing for `missingGraceMs`, so a
        // save never opens the API. A check long after the last one can't tell
        // whether the file came back in between, so its grace starts over, and
        // re-checks keep the checks close together. At startup there is nothing to keep.
        if (state?.on) {
          const at = now();
          missing =
            missing === undefined || at - missing.last > maxGapMs
              ? { since: at, last: at }
              : { since: missing.since, last: at };
          if (at - missing.since < missingGraceMs) {
            recheck();
            return state;
          }
        }
        missing = undefined;
        return settle({ on: false });
      }
      missing = undefined;
      // It exists but can't be read (a directory, no permission): on, admitting
      // no listed device, and tried again on the next request.
      stamp = undefined;
      const next = settle({ on: true, allowed: new Map() });
      if (!unreadable) {
        unreadable = true;
        log(
          `[auth] tailscale devices file ${path} can't be read, so no device is allowed: ${messageOf(error)}`,
        );
      }
      return next;
    }
    unreadable = false;
    missing = undefined;
    const allowed = parseDevices(text);
    const next = settle({ on: true, allowed });
    log(`[auth] tailscale devices file read: ${allowed.size} listed`);
    return next;
  };

  /** The current state, one stat per burst: concurrent requests share the read in flight. */
  const devices = (): Promise<DevicesState> =>
    (reading ??= read().finally(() => {
      reading = undefined;
    }));

  /** Checks the missing file again in `recheckMs`, request or not; one at a time. */
  const recheck = () => {
    if (recheckDue) return;
    recheckDue = true;
    schedule(async () => {
      recheckDue = false;
      await devices().catch(() => undefined);
      // That may have been a read already under way, whose own re-check found this one due.
      if (missing !== undefined) recheck();
    }, recheckMs);
  };

  // ── whois, cached per address: the promise is stored at once, so concurrent
  // first requests share one CLI run.
  const cache = new Map<string, { until: number; answer: Promise<WhoisResult | undefined> }>();
  const failed = new Set<string>(); // addresses whose failure was logged

  const whois = async (address: string): Promise<WhoisResult | undefined> => {
    try {
      const result = parseWhois(
        await withTimeout(exec(['whois', '--json', address], timeoutMs), timeoutMs),
      );
      failed.delete(address);
      return result;
    } catch (error) {
      if (!failed.has(address)) {
        failed.add(address);
        log(`[auth] tailscale whois ${address} failed: ${messageOf(error)}`);
      }
      return undefined;
    }
  };

  const resolve = (address: string): Promise<WhoisResult | undefined> => {
    const at = now();
    const hit = cache.get(address);
    if (hit !== undefined && hit.until > at) return hit.answer;
    const answer = whois(address);
    cache.set(address, { until: at + cacheMs, answer });
    if (cache.size > 1024) {
      for (const [key, entry] of cache) if (entry.until <= at) cache.delete(key);
    }
    return answer;
  };

  // ── This server's own node, learned on first need (never while the scheme is
  // off, so a machine that hasn't opted in runs no CLI). Kept for the process's
  // life once known; a failure is retried after `cacheMs`.
  let self: { until: number; id: Promise<string | undefined> } | undefined;
  let selfFailed = false;

  const learnSelf = async (): Promise<string | undefined> => {
    try {
      const id = parseSelf(
        await withTimeout(exec(['status', '--json'], statusTimeoutMs), statusTimeoutMs),
      );
      selfFailed = false;
      log(`[auth] tailscale this node (${id}) is always admitted`);
      return id;
    } catch (error) {
      if (!selfFailed) {
        selfFailed = true;
        log(`[auth] tailscale status failed, so this node isn't recognised: ${messageOf(error)}`);
      }
      return undefined;
    }
  };

  const selfID = (): Promise<string | undefined> => {
    const at = now();
    if (self === undefined || self.until <= at) {
      const entry = { until: at + cacheMs, id: learnSelf() };
      void entry.id.then((id) => {
        if (id !== undefined) entry.until = Infinity;
      });
      self = entry;
    }
    return self.id;
  };

  const decided = new Map<string, string>(); // device id → the last decision logged
  const decide = (device: Device, decision: string) => {
    if (decided.get(device.id) === decision) return;
    decided.set(device.id, decision);
    log(`[auth] tailscale device ${device.id} (${device.name}) ${decision}`);
  };

  const principal = async (req: PeerRequest): Promise<Verdict> => {
    const current = await devices();
    if (!current.on) return { scheme: 'open' };
    if (isLocalRequest(req)) return { scheme: 'local' };
    const address = forwardedTailnetAddress(req, apiHost);
    if (address === undefined) return undefined;
    const found = await resolve(address);
    if (found === undefined) return undefined;
    const { device, user } = found;
    const admit = (decision: string): Principal => {
      decide(device, decision);
      return { scheme: 'tailscale', device, ...(user === null ? {} : { user }) };
    };
    // A listed device needs no status call; only an unlisted one might be this server.
    if (current.allowed.has(device.id)) return admit('allowed');
    if (device.id === (await selfID())) return admit('is this server: allowed');
    decide(device, `not listed in ${path}: refused`);
    return { refused: device };
  };

  const middleware: RequestHandler = async (req, res, next) => {
    const verdict = await principal(req);
    if (isPrincipal(verdict)) {
      res.locals.principal = verdict;
      next();
      return;
    }
    const device = verdict?.refused ?? null;
    const message = device === null ? UNAUTHORIZED_UNKNOWN : UNAUTHORIZED_LISTED;
    // The top-level `message` is what the web app's useApiClient shows in its error toast.
    res
      .status(401)
      .set({ 'WWW-Authenticate': CHALLENGE, 'Cache-Control': 'no-store' })
      .json({ error: { code: 'unauthorized', message }, message, device });
  };

  // Read once now, so the on/off line is logged at startup rather than on the first request.
  void devices().catch(() => undefined);

  return { middleware, principal, enabled: async () => (await devices()).on };
}

/**
 * The scheme as the server runs it: the devices file from `ENCHIRIDION_DEVICES`
 * (else `~/.enchiridion/devices`), the CLI from `ENCHIRIDION_TAILSCALE` (else
 * `tailscale` on PATH), the public name from `ENCHIRIDION_API_HOST` (else
 * `DEFAULT_API_HOST`), logging to stdout.
 */
export function authFromEnv(env: NodeJS.ProcessEnv = process.env): TailscaleAuth {
  return createTailscaleAuth({
    devicesPath: devicesPathFrom(env),
    exec: tailscaleExec(env.ENCHIRIDION_TAILSCALE || 'tailscale'),
    apiHost: apiHostFrom(env),
    // eslint-disable-next-line no-console
    log: (line) => console.log(line),
  });
}
