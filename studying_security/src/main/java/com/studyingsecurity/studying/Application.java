package com.studyingsecurity.studying;

import java.util.HashSet;
import java.util.Set;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.security.crypto.password.PasswordEncoder;

import com.studyingsecurity.studying.model.ApplicationUser;
import com.studyingsecurity.studying.model.Role;
import com.studyingsecurity.studying.repository.RoleRepository;
import com.studyingsecurity.studying.repository.UserRepository;

@SpringBootApplication
public class Application {

	public static void main(String[] args) {
		SpringApplication.run(Application.class, args);
	}

	@Bean
	CommandLineRunner run(RoleRepository roleRepository, UserRepository userRepository, PasswordEncoder enconder) {
		return args -> {
			if (roleRepository.findByAuthority("ADMIN").isPresent()) {
				return;
			}
			Role adminRole = roleRepository.save(new Role(1, "ADMIN"));
			roleRepository.save(new Role(2, "USER"));
			Set<Role> roles = new HashSet<>();
			roles.add(adminRole);
			ApplicationUser applicationUser = new ApplicationUser(1, "admin", enconder.encode("password"), roles);
			userRepository.save(applicationUser);
		};
	}

}
