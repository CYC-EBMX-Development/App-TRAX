package com.trax.dto;

public class UserDto {
    private Long id;
    private String username;
    private String email;
    private String avatarUrl;

    public UserDto(Long id, String username, String email, String avatarUrl) {
        this.id = id;
        this.username = username;
        this.email = email;
        this.avatarUrl = avatarUrl;
    }

    public Long getId() { return id; }
    public String getUsername() { return username; }
    public String getEmail() { return email; }
    public String getAvatarUrl() { return avatarUrl; }
}
