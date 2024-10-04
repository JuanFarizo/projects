package annotations;

import annotations.annotation.InitializerClass;
import annotations.annotation.InitializerMethod;

@InitializerClass
public class AutoSaver {
    @InitializerMethod
    public void startAutoSavingThreads() {
        System.out.println("Start automatic data saving to disk");
    }
}
