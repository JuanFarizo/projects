package dynamic_proxy_reflec.external.impl;

import dynamic_proxy_reflec.external.HttpClient;

public class HttpClientImpl implements HttpClient {

    @Override
    public void initialize() {
        System.out.println("Initializing HTTP client");
        try {
            Thread.sleep(5000);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    @Override
    public String sendRequest(String request) {
        System.out.println(String.format("Sending request %s", request));
        try {
            Thread.sleep(1000);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
        System.out.println("Received Response");
        return "Some response";
    }

}
