package com.trax.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.trax.dto.LoginByPwdRequest;
import com.trax.dto.RegisterByPwdRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class AuthControllerTest {

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper objectMapper;

    private String json(Object body) throws Exception {
        return objectMapper.writeValueAsString(body);
    }

    @Test
    void registerThenLoginReturnsJwt() throws Exception {
        RegisterByPwdRequest reg = new RegisterByPwdRequest();
        reg.setEmail("integration-1@trax.com");
        reg.setPassword("password123");
        // verificationCode left null → skipped per controller logic

        mvc.perform(post("/api/auth/registerByPwd")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(reg)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.flag").value(true));

        LoginByPwdRequest login = new LoginByPwdRequest();
        login.setUsername("integration-1@trax.com");
        login.setPassword("password123");

        MvcResult res = mvc.perform(post("/api/auth/loginByPwd")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(login)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.flag").value(true))
                .andExpect(jsonPath("$.data.tokenType").value("Bearer"))
                .andExpect(jsonPath("$.data.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.data.user.email").value("integration-1@trax.com"))
                .andReturn();

        JsonNode body = objectMapper.readTree(res.getResponse().getContentAsString());
        assertThat(body.path("data").path("accessToken").asText()).contains(".");
    }

    @Test
    void verifyEmailReturnsOkForFreshEmail() throws Exception {
        mvc.perform(get("/api/auth/verify-email").param("email", "fresh-email@trax.com"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.flag").value(true));
    }

    @Test
    void verifyEmailFailsAfterRegistration() throws Exception {
        RegisterByPwdRequest reg = new RegisterByPwdRequest();
        reg.setEmail("dup-check@trax.com");
        reg.setPassword("password123");
        mvc.perform(post("/api/auth/registerByPwd")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(reg)))
                .andExpect(status().isOk());

        // Errors are wrapped by GlobalExceptionHandler → HTTP 200 with flag=false, code=40000
        mvc.perform(get("/api/auth/verify-email").param("email", "dup-check@trax.com"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.flag").value(false))
                .andExpect(jsonPath("$.code").value(40000))
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.containsString("already")));
    }

    @Test
    void loginWithWrongPasswordReturnsErrorPayload() throws Exception {
        RegisterByPwdRequest reg = new RegisterByPwdRequest();
        reg.setEmail("wrongpass@trax.com");
        reg.setPassword("correct-pwd");
        mvc.perform(post("/api/auth/registerByPwd")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(reg)))
                .andExpect(status().isOk());

        LoginByPwdRequest login = new LoginByPwdRequest();
        login.setUsername("wrongpass@trax.com");
        login.setPassword("WRONG");
        mvc.perform(post("/api/auth/loginByPwd")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(login)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.flag").value(false))
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.containsString("Incorrect password")));
    }

    @Test
    void loginWithUnknownAccountReturnsErrorPayload() throws Exception {
        LoginByPwdRequest login = new LoginByPwdRequest();
        login.setUsername("ghost-user@trax.com");
        login.setPassword("anything");
        mvc.perform(post("/api/auth/loginByPwd")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(login)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.flag").value(false))
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.containsString("Account not found")));
    }
}
