package com.trax.controller;

import com.trax.dto.ApiResponse;
import com.trax.dto.UpdateProfileRequest;
import com.trax.model.User;
import com.trax.service.UserService;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/users")
public class UserController {
    private static final Logger logger = LoggerFactory.getLogger(UserController.class);
    // Mirrors ImageController.IMAGES_DIR. Avatars are stored under <IMAGES_DIR>/avatars
    // and served by ImageController via GET /images/avatars/<file>.
    private static final String IMAGES_DIR = "/Users/cyc_joshua/Documents/CYC/TRAX/App-TRAX/backend/images";
    private static final String AVATAR_SUBDIR = "avatars";
    private static final long MAX_AVATAR_BYTES = 5L * 1024 * 1024; // 5 MB

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping("/me")
    public ResponseEntity<ApiResponse<Map<String, Object>>> getCurrentUser(Authentication auth) {
        User user = (User) auth.getPrincipal();
        return ResponseEntity.ok(ApiResponse.success(toDto(user)));
    }

    @PutMapping("/me")
    public ResponseEntity<ApiResponse<Map<String, Object>>> updateCurrentUser(
            Authentication auth, @RequestBody UpdateProfileRequest req) {
        User principal = (User) auth.getPrincipal();
        User patch = new User();
        if (req.getUsername() != null) patch.setName(req.getUsername());
        if (req.getAvatarUrl() != null) patch.setAvatarUrl(req.getAvatarUrl());
        User saved = userService.updateUser(principal.getId(), patch);
        return ResponseEntity.ok(ApiResponse.success(toDto(saved)));
    }

    @PostMapping("/me/avatar")
    public ResponseEntity<ApiResponse<Map<String, Object>>> uploadAvatar(
            Authentication auth,
            @RequestParam("file") MultipartFile file,
            HttpServletRequest request) {
        User principal = (User) auth.getPrincipal();
        if (file.isEmpty()) {
            return ResponseEntity.badRequest().body(ApiResponse.error(40001, "Empty file"));
        }
        if (file.getSize() > MAX_AVATAR_BYTES) {
            return ResponseEntity.badRequest().body(ApiResponse.error(40002, "File too large (max 5MB)"));
        }
        String originalRaw = file.getOriginalFilename();
        String original = (originalRaw != null && !originalRaw.isEmpty()) ? originalRaw : "avatar.jpg";
        String ext = "jpg";
        int dot = original.lastIndexOf('.');
        if (dot >= 0 && dot < original.length() - 1) {
            String e = original.substring(dot + 1).toLowerCase();
            if (e.matches("png|jpg|jpeg|webp|gif")) ext = e.equals("jpeg") ? "jpg" : e;
        }
        try {
            Path dir = Paths.get(IMAGES_DIR, AVATAR_SUBDIR);
            Files.createDirectories(dir);
            String filename = "u" + principal.getId() + "_" + System.currentTimeMillis() + "." + ext;
            Path target = dir.resolve(filename);
            try (var in = file.getInputStream()) {
                Files.copy(in, target, StandardCopyOption.REPLACE_EXISTING);
            }
            String publicUrl = buildPublicUrl(request, AVATAR_SUBDIR + "/" + filename);
            User patch = new User();
            patch.setAvatarUrl(publicUrl);
            User saved = userService.updateUser(principal.getId(), patch);
            return ResponseEntity.ok(ApiResponse.success(toDto(saved)));
        } catch (IOException e) {
            logger.error("Failed to save avatar for user {}", principal.getId(), e);
            return ResponseEntity.internalServerError()
                    .body(ApiResponse.error(50001, "Failed to save avatar"));
        }
    }

    private static Map<String, Object> toDto(User user) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", user.getId());
        m.put("email", user.getEmail());
        m.put("username", user.getName() != null ? user.getName() : "");
        m.put("name", user.getName() != null ? user.getName() : "");
        m.put("avatarUrl", user.getAvatarUrl() != null ? user.getAvatarUrl() : "");
        m.put("rewardPoints", user.getRewardPoints());
        return m;
    }

    private static String buildPublicUrl(HttpServletRequest request, String relativePath) {
        String scheme = request.getScheme();
        String host = request.getServerName();
        int port = request.getServerPort();
        boolean defaultPort = (scheme.equals("http") && port == 80) ||
                              (scheme.equals("https") && port == 443);
        String authority = defaultPort ? host : host + ":" + port;
        return scheme + "://" + authority + "/images/" + relativePath;
    }
}
