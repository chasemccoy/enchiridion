import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs/promises';
import sharp from 'sharp';
import crypto from 'crypto';
import { insertMedia, getMedia, deleteMedia, deleteMediaForRecord } from '@db/queries/media';
import {
  IdParamSchema,
  IdSchema,
  SUPPORTED_IMAGE_TYPES,
  SUPPORTED_MEDIA_TYPES,
  SUPPORTED_PDF_TYPES,
  SUPPORTED_VIDEO_TYPES,
} from '@shared/types/api';
import { z } from 'zod/v4';
import { deleteMediaFile } from '@api/utils';
import { UPLOADS_DIR } from '@shared/lib';

export const mediaRoutes = Router();

export const MAX_FILE_SIZE = 100 * 1024 * 1024; // 100MB

export const MediaUploadSchema = z.object({
  recordId: IdSchema.optional(),
  altText: z.string().optional(),
});

const IMAGES_DIR = path.join(UPLOADS_DIR, 'images');
const VIDEOS_DIR = path.join(UPLOADS_DIR, 'videos');
const PDFS_DIR = path.join(UPLOADS_DIR, 'pdfs');

// Ensure upload directories exist
async function ensureUploadDirs() {
  for (const dir of [UPLOADS_DIR, IMAGES_DIR, VIDEOS_DIR, PDFS_DIR]) {
    try {
      await fs.access(dir);
    } catch {
      await fs.mkdir(dir, { recursive: true });
    }
  }
}

// Initialize upload directories
ensureUploadDirs().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('Error creating upload directories:', error);
});

const storage = multer.memoryStorage();

const upload = multer({
  storage,
  limits: {
    fileSize: MAX_FILE_SIZE,
  },
  fileFilter: (_req, file, cb) => {
    if (SUPPORTED_MEDIA_TYPES.includes(file.mimetype as (typeof SUPPORTED_MEDIA_TYPES)[number])) {
      cb(null, true);
    } else {
      cb(new Error(`Unsupported file type: ${file.mimetype}`));
    }
  },
});

function getMediaDirectory(contentType: string): string {
  if (SUPPORTED_IMAGE_TYPES.includes(contentType as (typeof SUPPORTED_IMAGE_TYPES)[number])) {
    return IMAGES_DIR;
  } else if (
    SUPPORTED_VIDEO_TYPES.includes(contentType as (typeof SUPPORTED_VIDEO_TYPES)[number])
  ) {
    return VIDEOS_DIR;
  } else if (SUPPORTED_PDF_TYPES.includes(contentType as (typeof SUPPORTED_PDF_TYPES)[number])) {
    return PDFS_DIR;
  }
  return UPLOADS_DIR;
}

function getMediaType(contentType: string): string {
  if (SUPPORTED_IMAGE_TYPES.includes(contentType as (typeof SUPPORTED_IMAGE_TYPES)[number])) {
    return 'image';
  } else if (
    SUPPORTED_VIDEO_TYPES.includes(contentType as (typeof SUPPORTED_VIDEO_TYPES)[number])
  ) {
    return 'video';
  } else if (SUPPORTED_PDF_TYPES.includes(contentType as (typeof SUPPORTED_PDF_TYPES)[number])) {
    return 'application';
  }
  return 'application';
}

function getFileExtension(contentType: string): string {
  const extensions: Record<string, string> = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'video/mp4': '.mp4',
    'video/quicktime': '.mov',
    'video/x-msvideo': '.avi',
    'application/pdf': '.pdf',
  };
  return extensions[contentType] || '';
}

async function getImageDimensions(
  buffer: Buffer,
  contentType: string,
): Promise<{ width?: number; height?: number }> {
  if (SUPPORTED_IMAGE_TYPES.includes(contentType as (typeof SUPPORTED_IMAGE_TYPES)[number])) {
    try {
      const metadata = await sharp(buffer).metadata();
      return {
        width: metadata.width,
        height: metadata.height,
      };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('Error getting image dimensions:', error);
    }
  }
  return {};
}

// ============================================================================
// GET
// ============================================================================

mediaRoutes.get('/media/:id', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);
    const media = await getMedia(id);

    if (!media) {
      throw new Error('Media not found');
    }

    res.json(media);
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// POST
// ============================================================================

mediaRoutes.post('/media', upload.single('file'), async (req, res, next) => {
  try {
    if (!req.file) {
      throw new Error('No file provided');
    }

    const uploadData = MediaUploadSchema.parse(req.body);

    // Generate unique filename
    const fileId = crypto.randomUUID();
    const extension = getFileExtension(req.file.mimetype);
    const filename = `${fileId}${extension}`;

    // Determine storage directory and type
    const mediaDir = getMediaDirectory(req.file.mimetype);
    const filePath = path.join(mediaDir, filename);
    const mediaType = getMediaType(req.file.mimetype);

    // Get image dimensions if applicable
    const dimensions = await getImageDimensions(req.file.buffer, req.file.mimetype);

    // Save file to filesystem
    await fs.writeFile(filePath, req.file.buffer);

    // Create relative URL for database storage
    const relativePath = path.relative(UPLOADS_DIR, filePath);
    const url = `/uploads/${relativePath.replace(/\\/g, '/')}`;

    // Insert media record
    const mediaRecord = await insertMedia({
      recordId: uploadData.recordId || null,
      url,
      altText: uploadData.altText || null,
      type: mediaType,
      contentTypeString: req.file.mimetype,
      fileSize: req.file.size,
      width: dimensions.width || null,
      height: dimensions.height || null,
    });

    res.status(201).json(mediaRecord);
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// DELETE
// ============================================================================

mediaRoutes.delete('/media/:id', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);
    const media = await getMedia(id);

    if (!media) {
      throw new Error('Media not found');
    }

    await deleteMediaFile(media.url);

    const deleted = await deleteMedia(id);

    if (!deleted) {
      throw new Error('Media not found');
    }

    res.json(deleted);
  } catch (error) {
    next(error);
  }
});

mediaRoutes.delete('/media/record/:id', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);
    const media = await deleteMediaForRecord(id);

    await Promise.all(media.map((m) => deleteMediaFile(m.url)));

    res.json(media);
  } catch (error) {
    next(error);
  }
});
