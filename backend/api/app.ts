/**
 * Express app assembly, separated from the listener (index.ts) so tests can
 * exercise routes in-process via supertest without binding a port.
 */
import express from 'express';
import compression from 'compression';
import cors from 'cors';
import { eq } from 'drizzle-orm';
import { db } from '@db/index';
import { records } from '@db/schema';
import {
  ARCHIVE_CSP,
  authFromEnv,
  corsOptions,
  originGate,
  webOriginsFrom,
  type Principal,
} from './auth';
import { recordRoutes } from './records';
import { treeRoutes } from './tree';
import { linkRoutes } from './links';
import { errorHandler } from './errorHandler';
import { searchRoutes } from './search';
import { mediaRoutes } from './media';
import { twitterRoutes } from './twitter';
import { integrationRoutes } from './integrations';
import { archiveRoot } from '@integrations/archive';

export const app = express();

// Tailscale identity (auth.ts): off, with the API open, unless the devices file
// exists (ENCHIRIDION_DEVICES, else ~/.enchiridion/devices).
const auth = authFromEnv();
// The web app's own origins: while the scheme is on, the only pages a browser
// may call the API from (auth.ts, originGate).
const webOrigins = webOriginsFrom();

app.use(compression());
// The origin gate, CORS and auth run before the body parsers: the gate refuses
// other sites' pages outright, cors() answers preflights (which carry no
// credentials) and puts its headers on 401s so the web app can read them, and a
// refused request's body is never parsed.
app.use(originGate(webOrigins, auth.enabled));
app.use(cors(corsOptions(webOrigins, auth.enabled)));
// The one open route, so a client can tell "can't reach enchiridion" from
// "this device isn't on the list", and whether to expect a device check at all.
app.get('/info', async (_req, res) => {
  const on = await auth.enabled();
  res.set('Cache-Control', 'no-store').json({ name: 'enchiridion', auth: on ? ['tailscale'] : [] });
});
app.use(auth.middleware);
app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ extended: true, limit: '100mb' }));

// Who the auth middleware admitted this request as.
app.get('/me', (_req, res) => {
  const { scheme, device, user } = res.locals.principal as Principal;
  res.set('Cache-Control', 'no-store').json({ scheme, device: device ?? null, user: user ?? null });
});

// PUT /record upserts on id, so an update naming a record deleted elsewhere
// would insert a bare row under that id (a curate sends only {id, slug,
// isCurated}): an orphan in everyone's index. An update must name a record that
// exists; creates (no id) go through.
app.put('/record', async (req, res, next) => {
  try {
    const id: unknown = (req.body as { id?: unknown } | undefined)?.id;
    if (typeof id !== 'number') {
      next();
      return;
    }
    const [found] = await db
      .select({ id: records.id })
      .from(records)
      .where(eq(records.id, id))
      .limit(1);
    if (found !== undefined) {
      next();
      return;
    }
    const message = `Record ${id} doesn't exist (anymore), so it can't be updated.`;
    res.status(404).json({ error: { code: 'not_found', message }, message });
  } catch (error) {
    next(error);
  }
});
app.use(recordRoutes);
app.use(treeRoutes);
app.use(linkRoutes);
app.use(searchRoutes);
app.use(mediaRoutes);
app.use(twitterRoutes);
app.use(integrationRoutes);
app.use('/uploads', express.static('uploads'));
// Local web archives (faithful offline copies). Served from our own origin so
// they're always frameable, unlike the live URLs. Some keep their site's
// scripts, so while the scheme is on they're sandboxed (auth.ts, ARCHIVE_CSP):
// opened in a tab, those scripts can't call the API as the browser's device.
app.use(
  '/archives',
  (_req, res, next) => {
    if ((res.locals.principal as Principal).scheme !== 'open') {
      res.set('Content-Security-Policy', ARCHIVE_CSP);
    }
    next();
  },
  express.static(archiveRoot()),
);

// Error middleware must be mounted AFTER the routes it covers — Express only
// dispatches next(error) to handlers registered later in the chain.
app.use(errorHandler);
