import React, { useEffect, useState } from "react";

interface Video {
  id: string;
  title: string;
  thumbnail: string;
}

function App() {
  const [videos, setVideos] = useState<Video[]>([]);

  useEffect(() => {
    fetch("/api/videos")
      .then((res) => res.json())
      .then((data) => setVideos(data))
      .catch(() => setVideos([]));
  }, []);

  return (
    <div>
      <header>
        <h1>YouTube Clone</h1>
      </header>
      <main>
        <div className="video-grid">
          {videos.map((video) => (
            <div key={video.id} className="video-card">
              <img src={video.thumbnail} alt={video.title} />
              <h3>{video.title}</h3>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}

export default App;
