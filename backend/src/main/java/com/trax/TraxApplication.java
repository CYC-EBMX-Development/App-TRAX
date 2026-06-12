package com.trax;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class TraxApplication {
    public static void main(String[] args) {
        SpringApplication.run(TraxApplication.class, args);
    }
}
