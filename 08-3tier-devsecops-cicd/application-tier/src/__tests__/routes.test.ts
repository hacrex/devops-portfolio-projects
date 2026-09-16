import request from "supertest";
import { app } from "../index";

describe("GET /health", () => {
  it("should return healthy status", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("healthy");
  });
});

describe("GET /api/videos", () => {
  it("should return a list of videos", async () => {
    const res = await request(app).get("/api/videos");
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThan(0);
  });
});

describe("POST /api/videos", () => {
  it("should create a new video", async () => {
    const res = await request(app)
      .post("/api/videos")
      .send({ title: "Test Video" });
    expect(res.status).toBe(201);
    expect(res.body.title).toBe("Test Video");
    expect(res.body.id).toBeDefined();
  });

  it("should return 400 if title is missing", async () => {
    const res = await request(app)
      .post("/api/videos")
      .send({});
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("Title is required");
  });
});
