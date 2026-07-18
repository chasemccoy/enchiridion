import 'dotenv/config';
import express from 'express';
import compression from 'compression';
import { recordRoutes } from './records';
import { treeRoutes } from './tree';
import { linkRoutes } from './links';
import { errorHandler } from './errorHandler';
import cors from 'cors';
import { searchRoutes } from './search';
import { mediaRoutes } from './media';
import { twitterRoutes } from './twitter';
import { integrationRoutes } from './integrations';
import { archiveRoot } from '@integrations/archive';

const PORT = process.env.BACKEND_PORT;

const app = express();

app.use(compression());
app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ extended: true, limit: '100mb' }));
app.use(cors({ origin: '*' }));

app.use(errorHandler);
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

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Server running on port ${PORT}`);
});
