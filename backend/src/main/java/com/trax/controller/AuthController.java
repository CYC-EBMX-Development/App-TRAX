package com.trax.controller;

import com.trax.dto.*;
import com.trax.service.AuthService;
import com.trax.service.VerificationCodeService;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final AuthService authService;
    private final VerificationCodeService codeService;

    public AuthController(AuthService authService, VerificationCodeService codeService) {
        this.authService = authService;
        this.codeService = codeService;
    }

    /** Login with email and password. */
    @PostMapping("/loginByPwd")
    public ApiResponse<LoginData> loginByPwd(@RequestBody LoginByPwdRequest request) {
        LoginData data = authService.loginByPwd(request.getUsername(), request.getPassword());
        return ApiResponse.success("Login successful", data);
    }

    /**
     * Exchange a refresh token for a freshly-rotated (access, refresh) pair.
     * Stateless: no DB row \u2014 the refresh token's signature, expiry, and
     * {@code type=refresh} claim are the sole gate. The old refresh token
     * is implicitly discarded; clients MUST persist the returned pair.
     */
    @PostMapping("/refresh")
    public ApiResponse<LoginData> refresh(@RequestBody RefreshRequest request) {
        LoginData data = authService.refreshAccessToken(request.getRefreshToken());
        return ApiResponse.success("Token refreshed", data);
    }

    /** Check if email is available for registration (not already taken). */
    @GetMapping("/verify-email")
    public ApiResponse<Void> verifyEmail(@RequestParam String email) {
        authService.checkEmailAvailable(email);
        return ApiResponse.success("Email is available", null);
    }

    /** Send a 6-digit verification code to the given email (printed to console in dev). */
    @PostMapping("/send-code")
    public ApiResponse<Void> sendCode(@RequestParam String email) {
        codeService.generateAndStore(email);
        return ApiResponse.success("Verification code sent", null);
    }

    /** Register a new account with email, password, and verification code. */
    @PostMapping("/registerByPwd")
    public ApiResponse<Void> registerByPwd(@RequestBody RegisterByPwdRequest request) {
        // Verification temporarily disabled: skip code check when not provided.
        String code = request.getVerificationCode();
        if (code != null && !code.isBlank()) {
            if (!codeService.verify(request.getEmail(), code)) {
                throw new RuntimeException("Invalid or expired verification code");
            }
        }
        authService.register(request.getEmail(), request.getPassword());
        return ApiResponse.success("Registration successful", null);
    }

    /** Reset password using a verification code. */
    @PostMapping("/reset-password")
    public ApiResponse<Void> resetPassword(@RequestBody ResetPasswordRequest request) {
        if (!codeService.verify(request.getEmail(), request.getVerificationCode())) {
            throw new RuntimeException("Invalid or expired verification code");
        }
        authService.resetPassword(request.getEmail(), request.getNewPassword());
        return ApiResponse.success("Password reset successful", null);
    }

    /** DEV ONLY: Reset password without verification code. */
    @PostMapping("/dev-reset-password")
    public ApiResponse<Void> devResetPassword(@RequestBody ResetPasswordRequest request) {
        authService.resetPassword(request.getEmail(), request.getNewPassword());
        return ApiResponse.success("Password reset successful", null);
    }
}
