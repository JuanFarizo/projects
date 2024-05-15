package com.example.spring_security_for_learnx.security;

import org.springframework.security.authentication.AuthenticationCredentialsNotFoundException;
import org.springframework.security.authentication.AuthenticationProvider;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.stereotype.Component;

@Component
public class CustomAuthenticationProvider implements AuthenticationProvider {

    @Override
    public Authentication authenticate(Authentication authentication) throws AuthenticationException {
        String username = authentication.getName();
        String password = String.valueOf(authentication.getCredentials());
        // This condition generally calls UserDetailsService and PasswordEncoder to test
        // the username and password.
        if ("john".equals(username) && "12345".equals(password)) {
            return new UsernamePasswordAuthenticationToken(username, password);
        } else {
            throw new AuthenticationCredentialsNotFoundException("Error in authentication");
        }
    }

    @Override
    public boolean supports(Class<?> authentication) {
        return UsernamePasswordAuthenticationToken.class.isAssignableFrom(authentication);
    }

}
