CREATE TABLE IF NOT EXISTS movies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    release_year INTEGER NOT NULL CHECK (release_year > 1888 AND release_year <= 2100),
    rating DECIMAL(3,1) CHECK (rating >= 0 AND rating <= 10),
    genre VARCHAR(100),
    director VARCHAR(255),
    duration_minutes INTEGER CHECK (duration_minutes > 0),
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_movies_title ON movies (title);
CREATE INDEX idx_movies_genre ON movies (genre);
CREATE INDEX idx_movies_release_year ON movies (release_year);
CREATE INDEX idx_movies_created_by ON movies (created_by);

CREATE TRIGGER update_movies_updated_at
    BEFORE UPDATE ON movies
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
