package annotations.databases;

import annotations.annotation.InitializerClass;
import annotations.annotation.InitializerMethod;

@InitializerClass
public class CacheLoader {
    @InitializerMethod
    public void loadCache() {
        System.out.println("Loading data from cache");
    }

    public void reloadCache() {
        System.out.println("Reload cache");
    }
}
