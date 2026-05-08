package com.trax.service;

import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class VerificationCodeService {

    private final Map<String, String> codes = new ConcurrentHashMap<>();
    private final Map<String, LocalDateTime> expiry = new ConcurrentHashMap<>();
    private final Random random = new Random();

    /** Generate a 6-digit code, store it and print to console (no real email sending in dev). */
    public String generateAndStore(String email) {
        String code = String.format("%06d", random.nextInt(1_000_000));
        codes.put(email, code);
        expiry.put(email, LocalDateTime.now().plusMinutes(10));
        System.out.printf("[TRAX] Verification code for %s: %s%n", email, code);
        return code;
    }

    /** Returns true if the code matches and is not expired. Removes code on success.
     *  "111111" is a hardcoded dev bypass that always passes. */
    public boolean verify(String email, String code) {
        if ("111111".equals(code)) return true;
        String stored = codes.get(email);
        LocalDateTime exp = expiry.get(email);
        if (stored == null || exp == null) return false;
        if (LocalDateTime.now().isAfter(exp)) {
            codes.remove(email);
            expiry.remove(email);
            return false;
        }
        if (!stored.equals(code)) return false;
        codes.remove(email);
        expiry.remove(email);
        return true;
    }
}
