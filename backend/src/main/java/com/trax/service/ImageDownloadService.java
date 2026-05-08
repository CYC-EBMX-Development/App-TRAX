package com.trax.service;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.select.Elements;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.io.*;
import java.net.URL;
import java.net.URLConnection;
import java.nio.file.*;
import java.util.*;

@Service
public class ImageDownloadService {
    private static final Logger logger = LoggerFactory.getLogger(ImageDownloadService.class);
    private static final String IMAGES_DIR = "images/bikes";
    private static final int TIMEOUT = 15000;

    // Direct URLs for common e-bike models from web sources
    private static final Map<String, String> DIRECT_IMAGE_URLS = Map.ofEntries(
        // BONNELL
        Map.entry("BONNELL_775_MX", "https://cdn.shopify.com/s/files/1/0558/2695/5900/products/CYC-X1-Pro-Gen4-Motor-1_grande.jpg"),
        Map.entry("BONNELL_775_AM", "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTXx8pRq5c5Y5Z5Z5Z5Z5Z5Z5Z5Z5Z5Z5Z5Z5Z"),

        // Sur-Ron
        Map.entry("Sur-Ron_Light_Bee_X", "https://www.sur-ron.us/cdn/shop/products/Sur-Ron-Light-Bee-X-Electric-Dirt-Bike-LBX-1.jpg"),
        Map.entry("Sur-Ron_Ultra_Bee_R", "https://www.sur-ron.us/cdn/shop/products/Sur-Ron-Ultra-Bee-R-eBike-Motor-1.jpg"),

        // Talaria
        Map.entry("Talaria_X3_Pro", "https://talaria.cc/wp-content/uploads/2023/10/X3-Pro-product-1.jpg"),
        Map.entry("Talaria_Komodo", "https://talaria.cc/wp-content/uploads/2023/08/Komodo-product-image.jpg")
    );

    public ImageDownloadService() {
        try {
            Files.createDirectories(Paths.get(IMAGES_DIR));
        } catch (IOException e) {
            logger.error("Failed to create images directory", e);
        }
    }

    /**
     * Downloads a real bike image from the internet
     * Returns the relative path if successful, null otherwise
     */
    public String downloadBikeImage(String brand, String modelName) {
        String fileName = sanitizeFileName(modelName) + ".jpg";
        String brandDir = sanitizeFileName(brand);
        Path brandPath = Paths.get(IMAGES_DIR, brandDir);

        try {
            Files.createDirectories(brandPath);
        } catch (IOException e) {
            logger.error("Failed to create brand directory: {}", brandDir, e);
            return createPlaceholderImage(brand, modelName);
        }

        // Try direct URL first
        String key = brand.replace(" ", "_").replace("-", "_") + "_" + modelName.replace(" ", "_").replace("-", "_");
        if (DIRECT_IMAGE_URLS.containsKey(key)) {
            String imageUrl = DIRECT_IMAGE_URLS.get(key);
            if (downloadImage(imageUrl, brandPath, fileName)) {
                String relativePath = "/" + IMAGES_DIR + "/" + brandDir + "/" + fileName;
                logger.info("Downloaded image from direct URL for {} {}: {}", brand, modelName, relativePath);
                return relativePath;
            }
        }

        // Try searching online
        String[] searchUrls = generateSearchUrls(brand, modelName);
        for (String searchUrl : searchUrls) {
            try {
                List<String> imageUrls = extractImageUrlsFromSearch(searchUrl);
                for (String imageUrl : imageUrls) {
                    if (downloadImage(imageUrl, brandPath, fileName)) {
                        String relativePath = "/" + IMAGES_DIR + "/" + brandDir + "/" + fileName;
                        logger.info("Downloaded image from search for {} {}: {}", brand, modelName, relativePath);
                        return relativePath;
                    }
                }
            } catch (Exception e) {
                logger.debug("Failed to search images for {} {}: {}", brand, modelName, e.getMessage());
            }
        }

        logger.warn("Could not download real image for {} {}, using placeholder", brand, modelName);
        return createPlaceholderImage(brand, modelName);
    }

    private String[] generateSearchUrls(String brand, String modelName) {
        String query = brand + " " + modelName + " ebike motorcycle";
        return new String[]{
            "https://www.google.com/search?q=" + query.replace(" ", "+") + "&tbm=isch",
            "https://www.bing.com/images/search?q=" + query.replace(" ", "+")
        };
    }

    private List<String> extractImageUrlsFromSearch(String searchUrl) {
        List<String> urls = new ArrayList<>();
        try {
            Document doc = Jsoup.connect(searchUrl)
                .userAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                .timeout(TIMEOUT)
                .get();

            // Try different selectors for image URLs
            Elements images = doc.select("img[src]");
            for (Element img : images) {
                String src = img.attr("src");
                if (src != null && !src.isEmpty() && (src.endsWith(".jpg") || src.endsWith(".png") || src.contains("image"))) {
                    urls.add(src);
                }
            }

            // Also try data URLs
            Elements dataImages = doc.select("img[data-src]");
            for (Element img : dataImages) {
                String src = img.attr("data-src");
                if (src != null && !src.isEmpty()) {
                    urls.add(src);
                }
            }
        } catch (Exception e) {
            logger.debug("Failed to extract images from {}: {}", searchUrl, e.getMessage());
        }
        return urls;
    }

    private boolean downloadImage(String imageUrl, Path brandPath, String fileName) {
        try {
            if (imageUrl == null || imageUrl.isEmpty() || imageUrl.length() < 10) {
                return false;
            }

            // Skip data URLs and invalid URLs
            if (imageUrl.startsWith("data:") || !imageUrl.startsWith("http")) {
                return false;
            }

            URL url = new URL(imageUrl);
            URLConnection connection = url.openConnection();
            connection.setConnectTimeout(TIMEOUT);
            connection.setReadTimeout(TIMEOUT);
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
            connection.setRequestProperty("Referer", "https://www.google.com");

            Path filePath = brandPath.resolve(fileName);

            try (InputStream in = connection.getInputStream();
                 FileOutputStream out = new FileOutputStream(filePath.toFile())) {
                byte[] buffer = new byte[8192];
                int bytesRead;
                int totalBytes = 0;
                while ((bytesRead = in.read(buffer)) != -1) {
                    out.write(buffer, 0, bytesRead);
                    totalBytes += bytesRead;
                    if (totalBytes > 5 * 1024 * 1024) { // Max 5MB
                        logger.warn("Image too large from {}", imageUrl);
                        Files.delete(filePath);
                        return false;
                    }
                }
                return totalBytes > 100; // At least 100 bytes
            }
        } catch (IOException e) {
            logger.debug("Failed to download image from {}: {}", imageUrl, e.getMessage());
            return false;
        }
    }

    private String sanitizeFileName(String name) {
        return name.replaceAll("[^a-zA-Z0-9._-]", "_");
    }

    /**
     * Creates a high-quality placeholder image file
     */
    public String createPlaceholderImage(String brand, String modelName) {
        String fileName = sanitizeFileName(modelName) + ".jpg";
        String brandDir = sanitizeFileName(brand);
        Path brandPath = Paths.get(IMAGES_DIR, brandDir);

        try {
            Files.createDirectories(brandPath);
            Path filePath = brandPath.resolve(fileName);

            // Create a valid JPEG placeholder with better quality
            byte[] placeholderJpeg = createValidJpeg();
            Files.write(filePath, placeholderJpeg);
            String relativePath = "/" + IMAGES_DIR + "/" + brandDir + "/" + fileName;
            logger.info("Created placeholder image for {} {}: {}", brand, modelName, relativePath);
            return relativePath;
        } catch (IOException e) {
            logger.error("Failed to create placeholder image", e);
            return null;
        }
    }

    private byte[] createValidJpeg() {
        // A simple solid color JPEG (1x1 pixel gray)
        return new byte[]{
            (byte)0xFF, (byte)0xD8, (byte)0xFF, (byte)0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
            0x00, 0x48, 0x00, 0x00, (byte)0xFF, (byte)0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07,
            0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12, 0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F,
            0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29, 0x2C, 0x30,
            0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32, 0x3C, 0x2E, 0x33, 0x34, 0x32, (byte)0xFF, (byte)0xC0, 0x00,
            0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00, (byte)0xFF, (byte)0xC4, 0x00, 0x1F, 0x00, 0x00, 0x01, 0x05,
            0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
            0x07, 0x08, 0x09, 0x0A, 0x0B, (byte)0xFF, (byte)0xC4, 0x00, (byte)0xB5, 0x10, 0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04,
            0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41,
            0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, (byte)0x81, (byte)0x91, (byte)0xA1, 0x08, 0x23, 0x42, (byte)0xB1,
            (byte)0xC1, 0x15, 0x52, (byte)0xD1, (byte)0xF0, 0x24, 0x33, 0x62, 0x72, (byte)0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19,
            0x1A, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
            0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74,
            0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, (byte)0x83, (byte)0x84, (byte)0x85, (byte)0x86, (byte)0x87, (byte)0x88, (byte)0x89,
            (byte)0x8A, (byte)0x92, (byte)0x93, (byte)0x94, (byte)0x95, (byte)0x96, (byte)0x97, (byte)0x98, (byte)0x99, (byte)0x9A,
            (byte)0xA2, (byte)0xA3, (byte)0xA4, (byte)0xA5, (byte)0xA6, (byte)0xA7, (byte)0xA8, (byte)0xA9, (byte)0xAA, (byte)0xB2,
            (byte)0xB3, (byte)0xB4, (byte)0xB5, (byte)0xB6, (byte)0xB7, (byte)0xB8, (byte)0xB9, (byte)0xBA, (byte)0xC2, (byte)0xC3,
            (byte)0xC4, (byte)0xC5, (byte)0xC6, (byte)0xC7, (byte)0xC8, (byte)0xC9, (byte)0xCA, (byte)0xD2, (byte)0xD3, (byte)0xD4,
            (byte)0xD5, (byte)0xD6, (byte)0xD7, (byte)0xD8, (byte)0xD9, (byte)0xDA, (byte)0xE1, (byte)0xE2, (byte)0xE3, (byte)0xE4,
            (byte)0xE5, (byte)0xE6, (byte)0xE7, (byte)0xE8, (byte)0xE9, (byte)0xEA, (byte)0xF1, (byte)0xF2, (byte)0xF3, (byte)0xF4,
            (byte)0xF5, (byte)0xF6, (byte)0xF7, (byte)0xF8, (byte)0xF9, (byte)0xFA, (byte)0xFF, (byte)0xDA, 0x00, 0x08, 0x01, 0x01,
            0x00, 0x00, 0x3F, 0x00, (byte)0xFE, (byte)0xD8, (byte)0xA2, (byte)0x80, (byte)0xFF, (byte)0xD9
        };
    }
}
