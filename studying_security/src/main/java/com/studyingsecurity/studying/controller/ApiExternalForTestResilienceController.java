package com.studyingsecurity.studying.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class ApiExternalForTestResilienceController {

    @GetMapping("/external")
    public String forTestingPropourse() {
        return "Test well xD";
    }

}
