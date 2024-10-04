package annotations.config;

import annotations.annotation.InitializerClass;
import annotations.annotation.InitializerMethod;

@InitializerClass
public class ConfigLoader {
    @InitializerMethod
    public void loadAllConfigs() {
        System.out.println("Loading all configuration files");
    }
}
