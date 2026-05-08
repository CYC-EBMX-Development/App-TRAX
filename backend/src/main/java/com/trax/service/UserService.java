package com.trax.service;

import com.trax.model.User;
import com.trax.repository.UserRepository;
import org.springframework.stereotype.Service;

@Service
public class UserService {
    private final UserRepository userRepository;

    public UserService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    public User getUserByEmail(String email) {
        return userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("User not found"));
    }

    public User updateUser(Long id, User updatedUser) {
        User user = userRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("User not found"));
        if (updatedUser.getName() != null) user.setName(updatedUser.getName());
        if (updatedUser.getAvatarUrl() != null) user.setAvatarUrl(updatedUser.getAvatarUrl());
        return userRepository.save(user);
    }
}
