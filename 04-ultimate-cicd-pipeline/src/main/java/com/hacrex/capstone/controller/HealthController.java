package com.hacrex.capstone.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class HealthController {

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }

    @GetMapping("/ready")
    public Map<String, String> ready() {
        return Map.of("ready", "true");
    }

    @GetMapping("/api/endpoint")
    public Map<String, Object> apiEndpoint() {
        return Map.of(
                "message", "Capstone Microservice Running",
                "version", "1.0.0",
                "service", "capstone"
        );
    }
}
