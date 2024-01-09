package com.studyingsecurity.studying.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.studyingsecurity.studying.model.ApplicationUser;
import com.studyingsecurity.studying.model.LoginResponseDTO;
import com.studyingsecurity.studying.model.RegistrationDTO;
import com.studyingsecurity.studying.services.AuthenticationService;

@RestController
@RequestMapping("/auth")
@CrossOrigin("*")
public class AuthenticationController {

    @Autowired
    private AuthenticationService authenticationService;

    @PostMapping("/register")
    public ApplicationUser registerUser(@RequestBody RegistrationDTO dto) {
        return authenticationService.registerUser(dto.getUsername(), dto.getPassword());
    }

    @PostMapping("/login")
    public LoginResponseDTO loginUser(@RequestBody RegistrationDTO dto) {
        return authenticationService.loginUser(dto.getUsername(), dto.getPassword());
    }

}
