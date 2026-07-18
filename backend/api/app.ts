/**
 * Express app assembly, separated from the listener (index.ts) so tests can
 * exercise routes in-process via supertest without binding a port.
 */
import express from 'express';
import compression from 'compression';
import cors from 'cors';
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

app.use(compression());
app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ extended: true, limit: '100mb' }));
app.use(cors({ origin: '*' }));

app.use(recordRoutes);
app.use(treeRoutes);
app.use(linkRoutes);
app.use(searchRoutes);
app.use(mediaRoutes);
app.use(twitterRoutes);
app.use(integrationRoutes);
app.use('/uploads', express.static('uploads'));
// Local web archives (faithful, inert offline copies). Served from our own
// origin so they're always frameable, unlike the live URLs.
app.use('/archives', express.static(archiveRoot()));

// Error middleware must be mounted AFTER the routes it covers — Express only
// dispatches next(error) to handlers registered later in the chain.
app.use(errorHandler);
