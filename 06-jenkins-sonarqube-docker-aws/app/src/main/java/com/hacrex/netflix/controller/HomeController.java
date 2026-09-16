package com.hacrex.netflix.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.Map;

@RestController
public class HomeController {

    @GetMapping("/")
    public Map<String, String> home() {
        return Map.of(
            "service", "netflix-clone",
            "status", "running",
            "timestamp", LocalDateTime.now().toString()
        );
    }
}
