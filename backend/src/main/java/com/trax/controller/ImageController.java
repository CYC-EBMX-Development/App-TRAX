package com.trax.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

@RestController
@RequestMapping("/images")
public class ImageController {
    private static final Logger logger = LoggerFactory.getLogger(ImageController.class);
    private static final String IMAGES_DIR = "/Users/cyc_joshua/Documents/CYC/TRAX/App-TRAX/backend/images";

    @GetMapping("/**")
    public ResponseEntity<?> getImage(HttpServletRequest request) {
        try {
            // Extract the path from the request
            String requestPath = request.getRequestURI();
            String imagePath = requestPath.replace("/images/", "");

            Path file = Paths.get(IMAGES_DIR, imagePath);

            // Security check - prevent directory traversal
            if (!file.normalize().startsWith(Paths.get(IMAGES_DIR).normalize())) {
                return ResponseEntity.notFound().build();
            }

            if (!Files.exists(file)) {
                logger.warn("Image not found: {}", file);
                return ResponseEntity.notFound().build();
            }

            byte[] imageBytes = Files.readAllBytes(file);
            String name = file.getFileName().toString().toLowerCase();
            MediaType mediaType;
            if (name.endsWith(".png")) {
                mediaType = MediaType.IMAGE_PNG;
            } else if (name.endsWith(".gif")) {
                mediaType = MediaType.IMAGE_GIF;
            } else if (name.endsWith(".webp")) {
                mediaType = MediaType.parseMediaType("image/webp");
            } else if (name.endsWith(".svg")) {
                mediaType = MediaType.parseMediaType("image/svg+xml");
            } else {
                mediaType = MediaType.IMAGE_JPEG;
            }

            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_DISPOSITION, "inline")
                    .contentType(mediaType)
                    .body(imageBytes);
        } catch (IOException e) {
            logger.error("Error reading image file", e);
            return ResponseEntity.internalServerError().build();
        }
    }
}
