package com.studyingsecurity.studying.services;

import java.util.HashSet;
import java.util.Set;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.studyingsecurity.studying.model.ApplicationUser;
import com.studyingsecurity.studying.model.LoginResponseDTO;
import com.studyingsecurity.studying.model.Role;
import com.studyingsecurity.studying.repository.RoleRepository;
import com.studyingsecurity.studying.repository.UserRepository;

@Service
@Transactional
public class AuthenticationService {

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private RoleRepository roleRepository;

    @Autowired
    private PasswordEncoder encoder;

    @Autowired
    private AuthenticationManager manager; // from the configuration

    @Autowired
    private TokenService tokenService;

    public ApplicationUser registerUser(String username, String password) {
        String passwordEncoded = encoder.encode(password);
        Role userRele = roleRepository.findByAuthority("USER").get();
        Set<Role> authorities = new HashSet<>();
        authorities.add(userRele);

        return userRepository.save(new ApplicationUser(0, username, passwordEncoded, authorities));
    }

    /**
     * When send a request for a login user send the username and password to the
     * manager
     * which use the detail services given in the configuration, wrap the user and
     * generate the Authentication object
     * 
     * @param username
     * @param password
     * @return LoginResponseDTO
     */
    public LoginResponseDTO loginUser(String username, String password) {

        try {
            Authentication auth = manager.authenticate(
                    new UsernamePasswordAuthenticationToken(username, password));

            String token = tokenService.generateJwt(auth);

            return new LoginResponseDTO(userRepository.findByUsername(username).get(), token);
        } catch (AuthenticationException e) {
            return new LoginResponseDTO(null, "");
        }

    }
}
