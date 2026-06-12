package com.trax.dto;

/** Request body for {@code POST /api/auth/refresh}. */
public class RefreshRequest {
    private String refreshToken;

    public String getRefreshToken() { return refreshToken; }
    public void setRefreshToken(String refreshToken) { this.refreshToken = refreshToken; }
}
