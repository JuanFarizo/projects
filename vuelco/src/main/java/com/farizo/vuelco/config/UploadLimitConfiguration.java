package com.farizo.vuelco.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.util.unit.DataSize;

@Configuration
public class UploadLimitConfiguration {

    @Bean
    public FilterRegistrationBean<UploadPayloadLimitFilter> uploadPayloadLimitFilter(
            @Value("${spring.servlet.multipart.max-request-size}") DataSize maxRequestSize) {
        FilterRegistrationBean<UploadPayloadLimitFilter> registration = new FilterRegistrationBean<>();
        registration.setFilter(new UploadPayloadLimitFilter(maxRequestSize));
        registration.addUrlPatterns("/upload");
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE + 20);
        return registration;
    }
}
