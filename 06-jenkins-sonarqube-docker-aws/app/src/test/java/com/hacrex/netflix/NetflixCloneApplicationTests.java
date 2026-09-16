package com.hacrex.netflix.controller;

import com.hacrex.netflix.service.MovieService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import static org.junit.jupiter.api.Assertions.assertNotNull;

@SpringBootTest
class NetflixCloneApplicationTests {

    @Autowired
    private HomeController homeController;

    @MockitoBean
    private MovieService movieService;

    @Test
    void contextLoads() {
        assertNotNull(homeController);
    }
}
