import { Router, Request, Response } from "express";

const videoRoutes = Router();

const videos = [
  { id: "1", title: "DevOps Pipeline Setup", thumbnail: "/thumbs/1.jpg" },
  { id: "2", title: "Docker for Beginners", thumbnail: "/thumbs/2.jpg" },
  { id: "3", title: "Kubernetes Crash Course", thumbnail: "/thumbs/3.jpg" },
];

videoRoutes.get("/videos", (_req: Request, res: Response) => {
  res.json(videos);
});

videoRoutes.post("/videos", (req: Request, res: Response) => {
  const { title, thumbnail } = req.body;
  if (!title) {
    res.status(400).json({ error: "Title is required" });
    return;
  }
  const newVideo = {
    id: String(videos.length + 1),
    title,
    thumbnail: thumbnail || "/thumbs/default.jpg",
  };
  videos.push(newVideo);
  res.status(201).json(newVideo);
});

export { videoRoutes };
