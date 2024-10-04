package dynamic_proxy_reflec.external;

public interface HttpClient {
    void initialize();
    String sendRequest(String request);
}
