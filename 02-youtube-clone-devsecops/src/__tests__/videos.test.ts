import request from 'supertest';
import { app } from '../index';

describe('Video Routes', () => {
  describe('GET /api/videos', () => {
    it('should return list of videos', async () => {
      const res = await request(app).get('/api/videos');
      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
      expect(res.body.length).toBeGreaterThan(0);
    });
  });

  describe('GET /api/videos/:id', () => {
    it('should return a video by id', async () => {
      const res = await request(app).get('/api/videos/1');
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('id', '1');
      expect(res.body).toHaveProperty('title');
    });

    it('should return 404 for non-existent video', async () => {
      const res = await request(app).get('/api/videos/999');
      expect(res.status).toBe(404);
    });
  });

  describe('POST /api/videos', () => {
    it('should create a new video', async () => {
      const newVideo = {
        title: 'Test Video',
        description: 'Test description',
        url: 'https://example.com/test',
        thumbnailUrl: 'https://example.com/test-thumb.jpg'
      };
      const res = await request(app).post('/api/videos').send(newVideo);
      expect(res.status).toBe(201);
      expect(res.body).toHaveProperty('id');
      expect(res.body.title).toBe('Test Video');
      expect(res.body.viewCount).toBe(0);
    });

    it('should return 400 if title is missing', async () => {
      const res = await request(app).post('/api/videos').send({ url: 'https://example.com/test' });
      expect(res.status).toBe(400);
    });

    it('should return 400 if url is missing', async () => {
      const res = await request(app).post('/api/videos').send({ title: 'Test' });
      expect(res.status).toBe(400);
    });
  });

  describe('DELETE /api/videos/:id', () => {
    it('should delete a video', async () => {
      const res = await request(app).delete('/api/videos/1');
      expect(res.status).toBe(204);
    });

    it('should return 404 for non-existent video', async () => {
      const res = await request(app).delete('/api/videos/999');
      expect(res.status).toBe(404);
    });
  });

  describe('GET /health', () => {
    it('should return healthy status', async () => {
      const res = await request(app).get('/health');
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status', 'healthy');
    });
  });
});
