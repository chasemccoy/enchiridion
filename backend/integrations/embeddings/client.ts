import OpenAI from 'openai';
import { EMBEDDING_MODEL } from './constants';

let client: OpenAI | null = null;

/**
 * Whether embedding generation is configured. When `OPENAI_API_KEY` is absent
 * the whole embeddings layer no-ops so the app keeps working without it.
 */
export const isEmbeddingEnabled = (): boolean => Boolean(process.env.OPENAI_API_KEY);

const getClient = (): OpenAI => {
  if (!process.env.OPENAI_API_KEY) {
    throw new Error('OPENAI_API_KEY is not set');
  }
  if (!client) {
    client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
      // Keep request latency bounded so an on-write embedding can't hang a save.
      timeout: 20_000,
      maxRetries: 2,
    });
  }
  return client;
};

/**
 * Generate embeddings for a batch of texts. Returns vectors in the same order
 * as the inputs.
 */
export const embedTexts = async (texts: string[]): Promise<number[][]> => {
  if (texts.length === 0) return [];
  const response = await getClient().embeddings.create({
    model: EMBEDDING_MODEL,
    input: texts,
  });
  return response.data
    .slice()
    .sort((a, b) => a.index - b.index)
    .map((item) => item.embedding as number[]);
};
