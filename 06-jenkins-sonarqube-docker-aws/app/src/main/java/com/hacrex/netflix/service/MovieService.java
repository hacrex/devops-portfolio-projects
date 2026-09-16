package com.hacrex.netflix.service;

import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Service
public class MovieService {

    private final List<Map<String, String>> movies = List.of(
        Map.of("id", "1", "title", "The Matrix", "year", "1999"),
        Map.of("id", "2", "title", "Inception", "year", "2010"),
        Map.of("id", "3", "title", "Interstellar", "year", "2014")
    );

    public List<Map<String, String>> getAllMovies() {
        return movies;
    }

    public Map<String, String> getMovieById(String id) {
        return movies.stream()
            .filter(m -> m.get("id").equals(id))
            .findFirst()
            .orElseThrow(() -> new RuntimeException("Movie not found: " + id));
    }
}
