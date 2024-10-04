package annotations.http;

import annotations.annotation.InitializerClass;
import annotations.annotation.InitializerMethod;

@InitializerClass
public class ServiceRegistry {
    @InitializerMethod
    public void registerService() {
        System.out.println("Service successfully registered");
    }
}
