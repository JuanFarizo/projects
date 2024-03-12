package testing.singleton;

import java.util.HashMap;

public class CacheManager {
    private final HashMap<String, Object> map;
    private static CacheManager INSTANCE;

    private CacheManager() {
        map = new HashMap<String, Object>();
    }

    public static CacheManager getInstance() {
        if (INSTANCE == null) {
            INSTANCE = new CacheManager();
        }
        return INSTANCE;
    }

    public <T> T getValues(String key, Class<T> clazz) {
        return clazz.cast(map.get(key));
    }

    public Object setValue(String key, Object value) {
        return map.put(key, value);
    }
}
