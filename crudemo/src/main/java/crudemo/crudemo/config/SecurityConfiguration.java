package crudemo.crudemo.config;

import javax.sql.DataSource;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.provisioning.JdbcUserDetailsManager;
import org.springframework.security.provisioning.UserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
public class SecurityConfiguration {

        @Bean
        public UserDetailsManager userDetailsManager(DataSource ds) {
                JdbcUserDetailsManager dm = new JdbcUserDetailsManager(ds);
                dm.setUsersByUsernameQuery(
                                "select user_id, pw, active from members where user_id=?");
                dm.setGroupAuthoritiesByUsernameQuery(
                                "select user_id, role from roles where user_id=?");
                return dm;
        }

        @Bean
        public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
                http.authorizeHttpRequests(configurer -> configurer.requestMatchers(HttpMethod.GET, "api/employees")
                                .hasRole("EMPLOYEE")
                                .requestMatchers(HttpMethod.GET, "api/students/**").hasRole("EMPLOYEE")
                                .requestMatchers(HttpMethod.GET, "api/employees/**").hasRole("EMPLOYEE")
                                .requestMatchers(HttpMethod.POST, "api/employees").hasRole("MANAGER")
                                .requestMatchers(HttpMethod.PUT, "api/employees/**").hasRole("MANAGER")
                                .requestMatchers(HttpMethod.DELETE, "api/employees/**").hasRole("ADMIN"));

                http.csrf(csrf -> csrf.disable());
                http.httpBasic(Customizer.withDefaults());
                return http.build();
        }

        // @Bean
        // public InMemoryUserDetailsManager userDetailsManager() {
        // UserDetails john = User.builder()
        // .username("john")
        // .password("{noop}test123")
        // .roles("EMPLOYEE")
        // .build();

        // UserDetails mary = User.builder()
        // .username("mary")
        // .password("{noop}test123")
        // .roles("EMPLOYEE", "MANAGER")
        // .build();

        // UserDetails susan = User.builder()
        // .username("susan")
        // .password("{noop}test123")
        // .roles("EMPLOYEE", "MANAGER", "ADMIN")
        // .build();

        // return new InMemoryUserDetailsManager(john, mary, susan);
        // }

}
