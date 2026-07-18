import 'dotenv/config';
import { app } from './app';

const PORT = process.env.BACKEND_PORT;

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Server running on port ${PORT}`);
});
