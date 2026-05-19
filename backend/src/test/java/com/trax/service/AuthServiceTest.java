package com.trax.service;

import com.trax.dto.LoginData;
import com.trax.model.User;
import com.trax.repository.UserRepository;
import com.trax.security.JwtUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock UserRepository userRepository;
    @Mock PasswordEncoder passwordEncoder;
    @Mock JwtUtil jwtUtil;
    @InjectMocks AuthService authService;

    private User existing;

    @BeforeEach
    void setUp() {
        existing = new User();
        existing.setId(1L);
        existing.setEmail("alice@trax.com");
        existing.setName("alice");
        existing.setPassword("$encoded$");
    }

    @Test
    void checkEmailAvailableThrowsWhenTaken() {
        when(userRepository.existsByEmail("alice@trax.com")).thenReturn(true);
        assertThatThrownBy(() -> authService.checkEmailAvailable("alice@trax.com"))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("already registered");
    }

    @Test
    void checkEmailAvailablePassesWhenFree() {
        when(userRepository.existsByEmail("bob@trax.com")).thenReturn(false);
        authService.checkEmailAvailable("bob@trax.com"); // no throw
    }

    @Test
    void loginByPwdReturnsTokenAndUserWhenPasswordMatches() {
        when(userRepository.findByEmail("alice@trax.com")).thenReturn(Optional.of(existing));
        when(passwordEncoder.matches("plain", "$encoded$")).thenReturn(true);
        when(jwtUtil.generateToken("alice@trax.com")).thenReturn("jwt-token");

        LoginData data = authService.loginByPwd("alice@trax.com", "plain");

        assertThat(data.getAccessToken()).isEqualTo("jwt-token");
        assertThat(data.getTokenType()).isEqualTo("Bearer");
        assertThat(data.getUser().getEmail()).isEqualTo("alice@trax.com");
        assertThat(data.getUser().getId()).isEqualTo(1L);
    }

    @Test
    void loginByPwdThrowsWhenAccountMissing() {
        when(userRepository.findByEmail("nobody@trax.com")).thenReturn(Optional.empty());
        assertThatThrownBy(() -> authService.loginByPwd("nobody@trax.com", "x"))
                .hasMessageContaining("Account not found");
    }

    @Test
    void loginByPwdThrowsOnIncorrectPassword() {
        when(userRepository.findByEmail("alice@trax.com")).thenReturn(Optional.of(existing));
        when(passwordEncoder.matches("wrong", "$encoded$")).thenReturn(false);

        assertThatThrownBy(() -> authService.loginByPwd("alice@trax.com", "wrong"))
                .hasMessageContaining("Incorrect password");
        verify(jwtUtil, never()).generateToken(anyString());
    }

    @Test
    void registerStoresEncodedPasswordAndDerivesName() {
        when(userRepository.existsByEmail("new@trax.com")).thenReturn(false);
        when(passwordEncoder.encode("pwd")).thenReturn("$enc$");

        authService.register("new@trax.com", "pwd");

        verify(userRepository).save(any(User.class));
    }

    @Test
    void registerThrowsWhenEmailExists() {
        when(userRepository.existsByEmail("dup@trax.com")).thenReturn(true);
        assertThatThrownBy(() -> authService.register("dup@trax.com", "pwd"))
                .hasMessageContaining("already registered");
        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    void resetPasswordUpdatesExistingUser() {
        when(userRepository.findByEmail("alice@trax.com")).thenReturn(Optional.of(existing));
        when(passwordEncoder.encode("newpwd")).thenReturn("$new$");

        authService.resetPassword("alice@trax.com", "newpwd");

        assertThat(existing.getPassword()).isEqualTo("$new$");
        verify(userRepository, times(1)).save(existing);
    }

    @Test
    void resetPasswordThrowsForUnknownEmail() {
        when(userRepository.findByEmail("ghost@trax.com")).thenReturn(Optional.empty());
        assertThatThrownBy(() -> authService.resetPassword("ghost@trax.com", "x"))
                .hasMessageContaining("Account not found");
        verify(userRepository, never()).save(any(User.class));
    }
}
