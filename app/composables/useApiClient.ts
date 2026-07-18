export enum ApiEndpoints {
  records = '/records',
}

const { BACKEND_PORT } = import.meta.env;

const defaultHeaders = {
  'Content-Type': 'application/json',
};

export default function useApiClient() {
  const hostname = window.location.hostname;
  let backendBaseUrl = `http://${hostname}:${BACKEND_PORT}`;

  if (hostname.includes('enchiridion')) {
    backendBaseUrl = 'https://enchiridion-api.chsmc.tools';
  }

  async function fetch<T>(
    endpoint: ApiEndpoints | string,
    options?: RequestInit,
    formData: boolean = false,
  ): Promise<T> {
    const url = new URL(endpoint, backendBaseUrl);

    const { headers, ...restOptions } = options ?? {};

    const optionsWithDefaults = {
      headers: formData
        ? undefined
        : {
            ...defaultHeaders,
            ...headers,
          },
      ...restOptions,
    };

    let response;

    try {
      response = await window.fetch(url, optionsWithDefaults);
    } catch (error) {
      throw new Error(`Error in useApiClient: ${error}`, { cause: error });
    }

    if (!response.ok) {
      const body = await response.text();
      let message: string | undefined;
      try {
        // The backend's errorHandler responds with { message } — prefer that
        // over the raw body so callers can show the error to the user as-is.
        message = (JSON.parse(body) as { message?: string }).message;
      } catch {
        // Non-JSON error body; fall through to the raw text.
      }
      throw new Error(message || body || `Request failed with status ${response.status}`);
    }

    return response.json();
  }

  return {
    backendBaseUrl,
    fetch,
  };
}
