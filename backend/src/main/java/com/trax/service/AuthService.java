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

    /** Verify a password against the stored hash for the given user.
     *  Throws if it does not match. Used by the in-app "Change Password"
     *  wizard step 1 (verify current password before showing step 2). */
    public void verifyPassword(Long userId, String password) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("Account not found"));
        if (!passwordEncoder.matches(password, user.getPassword())) {
            throw new RuntimeException("Current password is incorrect");
        }
    }

    /**
     * Change the password for an already-authenticated user. The caller
     * must supply the current (old) password — we verify it matches the
     * stored bcrypt hash before persisting the new password. Used by the
     * in-app "Change Password" flow in Profile → Settings.
     */
    public void changePassword(Long userId, String oldPassword, String newPassword) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("Account not found"));
        if (!passwordEncoder.matches(oldPassword, user.getPassword())) {
            throw new RuntimeException("Current password is incorrect");
        }
        if (newPassword == null || newPassword.length() < 6) {
            throw new RuntimeException("New password must be at least 6 characters");
        }
        if (passwordEncoder.matches(newPassword, user.getPassword())) {
            throw new RuntimeException("New password must differ from the current one");
        }
        user.setPassword(passwordEncoder.encode(newPassword));
        userRepository.save(user);
    }

    private LoginData buildLoginData(User user) {
        String accessToken = jwtUtil.generateToken(user.getEmail());
        String refreshToken = jwtUtil.generateRefreshToken(user.getEmail());
        UserDto userDto = new UserDto(user.getId(), user.getName(), user.getEmail(), AvatarUrls.versioned(user));
        return new LoginData(accessToken, refreshToken, "Bearer", userDto);
    }

    /**
     * Exchange a still-valid refresh token for a fresh (access, refresh)
     * pair. The old refresh token is implicitly discarded — callers must
     * persist the new one. Stateless: no DB lookup, signature + expiry
     * + {@code type=refresh} claim are the sole gate.
     *
     * @throws RuntimeException with HTTP-401-ish semantics when the token
     *         is missing, malformed, expired, signed with the wrong key,
     *         or carries the wrong type claim. The caller (Spring
     *         ControllerAdvice) maps this to a 401 response body.
     */
    public LoginData refreshAccessToken(String refreshToken) {
        if (refreshToken == null || refreshToken.isBlank()) {
            throw new RuntimeException("Missing refresh token");
        }
        if (!jwtUtil.validateToken(refreshToken) || !jwtUtil.isRefreshToken(refreshToken)) {
            throw new RuntimeException("Invalid or expired refresh token");
        }
        String email = jwtUtil.extractEmail(refreshToken);
        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("Account not found"));
        return buildLoginData(user);
    }
}
