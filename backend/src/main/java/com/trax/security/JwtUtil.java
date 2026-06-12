package com.trax.security;

import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;

@Component
public class JwtUtil {
    /** Claim name marking the token type (access vs refresh). */
    public static final String CLAIM_TYPE = "type";
    public static final String TYPE_ACCESS = "access";
    public static final String TYPE_REFRESH = "refresh";

    private final SecretKey key;
    private final long accessExpiration;
    private final long refreshExpiration;

    public JwtUtil(
            @Value("${jwt.secret}") String secret,
            @Value("${jwt.expiration}") long expiration,
            @Value("${jwt.refresh-expiration:7776000000}") long refreshExpiration) {
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.accessExpiration = expiration;
        this.refreshExpiration = refreshExpiration;
    }

    /** Generate a short-lived access token (default 30d). */
    public String generateToken(String email) {
        return buildToken(email, accessExpiration, TYPE_ACCESS);
    }

    /** Generate a long-lived refresh token (default 90d). */
    public String generateRefreshToken(String email) {
        return buildToken(email, refreshExpiration, TYPE_REFRESH);
    }

    private String buildToken(String subject, long ttlMillis, String type) {
        Date now = new Date();
        return Jwts.builder()
                .subject(subject)
                .issuedAt(now)
                .expiration(new Date(now.getTime() + ttlMillis))
                .claim(CLAIM_TYPE, type)
                .signWith(key)
                .compact();
    }

    public String extractEmail(String token) {
        return parseClaims(token).getSubject();
    }

    /**
     * Returns the token type claim, or {@code TYPE_ACCESS} for legacy
     * tokens issued before the refresh feature shipped. Callers should
     * use {@link #isAccessToken(String)} / {@link #isRefreshToken(String)}
     * instead of comparing raw strings.
     */
    public String extractType(String token) {
        Object raw = parseClaims(token).get(CLAIM_TYPE);
        return raw == null ? TYPE_ACCESS : raw.toString();
    }

    public boolean isAccessToken(String token) {
        try {
            return TYPE_ACCESS.equals(extractType(token));
        } catch (JwtException e) {
            return false;
        }
    }

    public boolean isRefreshToken(String token) {
        try {
            return TYPE_REFRESH.equals(extractType(token));
        } catch (JwtException e) {
            return false;
        }
    }

    /** Validate signature + expiry (does NOT check the type claim). */
    public boolean validateToken(String token) {
        try {
            parseClaims(token);
            return true;
        } catch (JwtException e) {
            return false;
        }
    }

    private Claims parseClaims(String token) {
        return Jwts.parser()
                .verifyWith(key)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }
}
