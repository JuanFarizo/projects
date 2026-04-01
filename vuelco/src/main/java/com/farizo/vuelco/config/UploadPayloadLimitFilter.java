package com.farizo.vuelco.config;

import java.io.IOException;

import org.springframework.util.unit.DataSize;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Rejects oversized multipart bodies early when Content-Length is known, before Spring parses the
 * request. Chunked uploads without Content-Length still rely on Tomcat / Spring limits.
 */
public class UploadPayloadLimitFilter extends OncePerRequestFilter {

    public static final String SESSION_FLASH_ERROR = "uploadFlashError";
    public static final String SESSION_FLASH_STEP = "uploadFlashStep";

    private final long maxRequestBytes;

    public UploadPayloadLimitFilter(DataSize maxRequestSize) {
        this.maxRequestBytes = maxRequestSize.toBytes();
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            filterChain.doFilter(request, response);
            return;
        }

        String path = request.getRequestURI();
        String contextPath = request.getContextPath();
        String uploadPath = contextPath.isEmpty() ? "/upload" : contextPath + "/upload";
        if (!path.equals(uploadPath)) {
            filterChain.doFilter(request, response);
            return;
        }

        String contentType = request.getContentType();
        if (contentType == null || !contentType.toLowerCase().startsWith("multipart/")) {
            filterChain.doFilter(request, response);
            return;
        }

        long contentLength = request.getContentLengthLong();
        if (contentLength >= 0 && contentLength > maxRequestBytes) {
            HttpSession session = request.getSession();
            session.setAttribute(SESSION_FLASH_ERROR,
                    "Se superó el tamaño máximo permitido para la carga (50 MB en total).");
            session.setAttribute(SESSION_FLASH_STEP, 1);
            response.sendRedirect(response.encodeRedirectURL(request.getContextPath() + "/"));
            return;
        }

        filterChain.doFilter(request, response);
    }
}
