package com.resilience.studying;

import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

@Component
public class ExternalAPICaller {

    private final RestTemplate restTemplate;

    public ExternalAPICaller(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    public String callApi() {
        return restTemplate.getForObject("/api/external", String.class);
    }

    public String callApiWithDelay() {
        String result = restTemplate.getForObject("/api/external", String.class);
        try {
            Thread.sleep(5000);
        } catch (InterruptedException ignore) {
        }
        return result;
    }

}
