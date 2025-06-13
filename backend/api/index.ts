import 'dotenv/config';
import express from 'express';
import { recordRoutes } from './records';
import { treeRoutes } from './tree';
import { linkRoutes } from './links';
import { errorHandler } from './errorHandler';
import cors from 'cors';
import { searchRoutes } from 'backend/api/search';
import { mediaRoutes } from './media';

const PORT = process.env.BACKEND_PORT;

const app = express();

app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ extended: true, limit: '100mb' }));
app.use(cors());

app.use(errorHandler);
app.use(recordRoutes);
app.use(treeRoutes);
app.use(linkRoutes);
app.use(searchRoutes);
app.use(mediaRoutes);
app.use('/uploads', express.static('uploads'));

app.listen(PORT, () => {
	// eslint-disable-next-line no-console
	console.log(`Server running on port ${PORT}`);
});
