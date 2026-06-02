package com.trax.security;

import io.jsonwebtoken.ExpiredJwtException;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtUtilTest {

    private static final String SECRET = "trax-secret-key-for-jwt-token-generation-min-256-bits-long-key";
    private static final long ONE_HOUR_MS = 3_600_000L;

    @Test
    void generatedTokenContainsEmailAsSubject() {
        JwtUtil util = new JwtUtil(SECRET, ONE_HOUR_MS);
        String token = util.generateToken("alice@trax.com");

        assertThat(token).isNotBlank().contains(".");
        assertThat(util.extractEmail(token)).isEqualTo("alice@trax.com");
    }

    @Test
    void validateTokenReturnsTrueForFreshToken() {
        JwtUtil util = new JwtUtil(SECRET, ONE_HOUR_MS);
        String token = util.generateToken("bob@trax.com");

        assertThat(util.validateToken(token)).isTrue();
    }

    @Test
    void validateTokenReturnsFalseForTamperedToken() {
        JwtUtil util = new JwtUtil(SECRET, ONE_HOUR_MS);
        String token = util.generateToken("carol@trax.com");
        String tampered = token.substring(0, token.length() - 4) + "AAAA";

        assertThat(util.validateToken(tampered)).isFalse();
    }

    @Test
    void validateTokenReturnsFalseForGarbageString() {
        JwtUtil util = new JwtUtil(SECRET, ONE_HOUR_MS);
        assertThat(util.validateToken("not-a-jwt")).isFalse();
    }

    @Test
    void tokenSignedWithDifferentSecretFailsValidation() {
        JwtUtil signer = new JwtUtil(SECRET, ONE_HOUR_MS);
        JwtUtil verifier = new JwtUtil(
                "another-secret-key-for-jwt-token-generation-min-256-bits-long-key",
                ONE_HOUR_MS);
        String token = signer.generateToken("dave@trax.com");

        assertThat(verifier.validateToken(token)).isFalse();
    }

    @Test
    void expiredTokenIsInvalidAndExtractThrows() {
        JwtUtil util = new JwtUtil(SECRET, -1_000L);
        String token = util.generateToken("eve@trax.com");

        assertThat(util.validateToken(token)).isFalse();
        assertThatThrownBy(() -> util.extractEmail(token))
                .isInstanceOf(ExpiredJwtException.class);
    }
}
