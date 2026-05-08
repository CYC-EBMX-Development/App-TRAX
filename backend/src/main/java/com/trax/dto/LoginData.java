package com.trax.dto;

public class LoginData {
    private String accessToken;
    private String tokenType;
    private UserDto user;

    public LoginData(String accessToken, String tokenType, UserDto user) {
        this.accessToken = accessToken;
        this.tokenType = tokenType;
        this.user = user;
    }

    public String getAccessToken() { return accessToken; }
    public String getTokenType() { return tokenType; }
    public UserDto getUser() { return user; }
}
