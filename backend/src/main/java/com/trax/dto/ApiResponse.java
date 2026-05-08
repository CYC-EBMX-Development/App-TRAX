package com.trax.dto;

public class ApiResponse<T> {
    private boolean flag;
    private int code;
    private String message;
    private T data;

    public ApiResponse(boolean flag, int code, String message, T data) {
        this.flag = flag;
        this.code = code;
        this.message = message;
        this.data = data;
    }

    public static <T> ApiResponse<T> success(String message, T data) {
        return new ApiResponse<>(true, 200, message, data);
    }

    public static <T> ApiResponse<T> success(T data) {
        return new ApiResponse<>(true, 200, "success", data);
    }

    public static <T> ApiResponse<T> error(int code, String message) {
        return new ApiResponse<>(false, code, message, null);
    }

    public boolean isFlag() { return flag; }
    public int getCode() { return code; }
    public String getMessage() { return message; }
    public T getData() { return data; }
}
