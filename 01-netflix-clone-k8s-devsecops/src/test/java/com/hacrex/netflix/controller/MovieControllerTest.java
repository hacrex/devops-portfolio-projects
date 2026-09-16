package com.hacrex.netflix.controller;

import com.hacrex.netflix.model.Movie;
import com.hacrex.netflix.service.MovieService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.bean.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.Optional;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(MovieController.class)
class MovieControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private MovieService movieService;

    @Test
    void getAllMovies_returnsList() throws Exception {
        Movie movie = new Movie("The Matrix", "A sci-fi action film", "Sci-Fi", 1999, "http://example.com/matrix.jpg");
        when(movieService.getAllMovies()).thenReturn(List.of(movie));

        mockMvc.perform(get("/api/movies"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].title", is("The Matrix")));
    }

    @Test
    void getMovieById_found() throws Exception {
        Movie movie = new Movie("Inception", "A dream within a dream", "Sci-Fi", 2010, "http://example.com/inception.jpg");
        movie.setId(1L);
        when(movieService.getMovieById(1L)).thenReturn(Optional.of(movie));

        mockMvc.perform(get("/api/movies/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.title", is("Inception")))
                .andExpect(jsonPath("$.genre", is("Sci-Fi")));
    }

    @Test
    void getMovieById_notFound() throws Exception {
        when(movieService.getMovieById(999L)).thenReturn(Optional.empty());

        mockMvc.perform(get("/api/movies/999"))
                .andExpect(status().isNotFound());
    }
}
