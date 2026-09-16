import { Router, Request, Response, NextFunction } from 'express';
import { Video } from '../models/Video';

export const videoRoutes = Router();

const videos: Video[] = [
  {
    id: '1',
    title: 'Introduction to DevSecOps',
    description: 'Learn the basics of DevSecOps',
    url: 'https://example.com/video1',
    thumbnailUrl: 'https://example.com/thumb1.jpg',
    viewCount: 1234,
    createdAt: new Date('2024-01-15')
  },
  {
    id: '2',
    title: 'Docker Security Best Practices',
    description: 'Securing your Docker containers',
    url: 'https://example.com/video2',
    thumbnailUrl: 'https://example.com/thumb2.jpg',
    viewCount: 5678,
    createdAt: new Date('2024-02-20')
  }
];

videoRoutes.get('/', (_req: Request, res: Response) => {
  res.json(videos);
});

videoRoutes.get('/:id', (req: Request, res: Response, next: NextFunction) => {
  const video = videos.find(v => v.id === req.params.id);
  if (!video) {
    const error = new Error('Video not found') as Error & { statusCode: number };
    error.statusCode = 404;
    return next(error);
  }
  res.json(video);
});

videoRoutes.post('/', (req: Request, res: Response) => {
  const { title, description, url, thumbnailUrl } = req.body;

  if (!title || !url) {
    const error = new Error('Title and URL are required') as Error & { statusCode: number };
    error.statusCode = 400;
    throw error;
  }

  const newVideo: Video = {
    id: String(videos.length + 1),
    title,
    description: description || '',
    url,
    thumbnailUrl: thumbnailUrl || '',
    viewCount: 0,
    createdAt: new Date()
  };

  videos.push(newVideo);
  res.status(201).json(newVideo);
});

videoRoutes.delete('/:id', (req: Request, res: Response, next: NextFunction) => {
  const index = videos.findIndex(v => v.id === req.params.id);
  if (index === -1) {
    const error = new Error('Video not found') as Error & { statusCode: number };
    error.statusCode = 404;
    return next(error);
  }
  videos.splice(index, 1);
  res.status(204).send();
});
