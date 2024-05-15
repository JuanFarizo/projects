package com.example.spring_security_for_learnx.config;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.crypto.password.NoOpPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;

import com.example.spring_security_for_learnx.security.CustomAuthenticationProvider;

@Configuration
public class ProjectConfig {

    @Autowired
    private CustomAuthenticationProvider authenticationProvider;

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.authorizeHttpRequests((authz) -> authz
                .anyRequest().authenticated())
                .httpBasic(Customizer.withDefaults());
        // InMemoryUserDetailsManager userDetailsService = new
        // InMemoryUserDetailsManager();

        // var user = User.withUsername("john")
        // .password("12345")
        // .authorities("read").build();

        // userDetailsService.createUser(user);
        // http.userDetailsService(userDetailsService);
        http.authenticationProvider(authenticationProvider);
        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return NoOpPasswordEncoder.getInstance();
    }

}
