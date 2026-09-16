import express from 'express';

const app = express();
app.use(express.json());

app.get('/health', (_req, res) => {
  res.json({ status: 'healthy' });
});

app.get('/ready', (_req, res) => {
  res.json({ ready: true });
});

app.get('/api/data', (_req, res) => {
  res.json({ data: 'success', version: '1.0.0' });
});

const PORT = process.env.PORT || 3000;

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
  });
}

export default app;
