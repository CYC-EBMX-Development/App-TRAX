package com.trax.service;

import com.trax.dto.LoginData;
import com.trax.dto.UserDto;
import com.trax.model.User;
import com.trax.repository.UserRepository;
import com.trax.security.JwtUtil;
import com.trax.util.AvatarUrls;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
public class AuthService {
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;

    public AuthService(UserRepository userRepository, PasswordEncoder passwordEncoder, JwtUtil jwtUtil) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtUtil = jwtUtil;
    }

    /** Verify the email is not already registered. Throws if taken. */
    public void checkEmailAvailable(String email) {
        if (userRepository.existsByEmail(email)) {
            throw new RuntimeException("Email already registered");
        }
    }

    /** Login with email (passed as username) and password. */
    public LoginData loginByPwd(String email, String password) {
        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("Account not found"));
        if (!passwordEncoder.matches(password, user.getPassword())) {
            throw new RuntimeException("Incorrect password");
        }
        return buildLoginData(user);
    }

    /** Register a new user. Email uniqueness should already be verified by verify-email step. */
    public void register(String email, String password) {
        if (userRepository.existsByEmail(email)) {
            throw new RuntimeException("Email already registered");
        }
        User user = new User();
        user.setEmail(email);
        user.setName(email.split("@")[0]);
        user.setPassword(passwordEncoder.encode(password));
        userRepository.save(user);
    }

    /** Reset password for an existing account. */
    public void resetPassword(String email, String newPassword) {
        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("Account not found"));
        user.setPassword(passwordEncoder.encode(newPassword));
        userRepository.save(user);
    }

    private LoginData buildLoginData(User user) {
        String token = jwtUtil.generateToken(user.getEmail());
        UserDto userDto = new UserDto(user.getId(), user.getName(), user.getEmail(), AvatarUrls.versioned(user));
        return new LoginData(token, "Bearer", userDto);
    }
}
