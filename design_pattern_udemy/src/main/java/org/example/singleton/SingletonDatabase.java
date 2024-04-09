package org.example.singleton;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;

import com.google.common.collect.Iterables;

interface Database { // In order to not have a hard dependency of the SingletonClass Implementation
    int getPopulation(String name);
}

public class SingletonDatabase implements Database {
    private Map<String, Integer> capitals = new HashMap<>();
    private static int instanceCount = 0;

    public static int getCount() {
        return instanceCount;
    }

    private SingletonDatabase() {
        instanceCount++;
        System.out.println("Initializing dtabase");

        try {
            File f = new File(
                    SingletonDatabase.class.getProtectionDomain()
                            .getCodeSource().getLocation().getPath());
            Path fullPath = Paths.get(f.getPath(), "capitals.txt");
            List<String> lines = Files.readAllLines(fullPath);

            Iterables.partition(lines, 2)
                    .forEach(kv -> capitals.put(kv.get(0).trim(), Integer.parseInt(kv.get(1))));
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static final SingletonDatabase INSTANCE = new SingletonDatabase();

    public static SingletonDatabase getInstance() {
        return INSTANCE;
    }

    public int getPopulation(String name) {
        return capitals.get(name);
    }
}

class SingletonRecordFinder {
    public int getTotalPopulation(List<String> names) {
        int result = 0;
        for (String name : names) {
            result += SingletonDatabase.getInstance().getPopulation(name);
        }
        return result;
    }
}

class ConfigurableRecordFinder {
    private Database database;

    public ConfigurableRecordFinder(Database database) {
        this.database = database;
    }

    public int getTotalPopulation(List<String> names) {
        int result = 0;
        for (String name : names) {
            result += database.getPopulation(name);
        }
        return result;
    }
}

class DummyDatabase implements Database {
    private Map<String, Integer> data = new HashMap<>();

    public DummyDatabase() {
        this.data.put("Alpha", 1);
        this.data.put("Betha", 2);
        this.data.put("Gamma", 3);
    }

    @Override
    public int getPopulation(String name) {
        return this.data.get(name);
    }

}

class DemoTest {
    @Test // This is an integration test
    void singletonTotalPopulationTest() {
        SingletonRecordFinder rf = new SingletonRecordFinder();
        List<String> names = List.of("Seoul", "Mexico City");
        int tp = rf.getTotalPopulation(names);
        assertEquals(1750000 + 1740000, tp);
    }

    @Test
    void dependentPopulationTest() {
        DummyDatabase db = new DummyDatabase();
        ConfigurableRecordFinder rf = new ConfigurableRecordFinder(db);
        assertEquals(4, rf.getTotalPopulation(List.of("Alpha", "Gamma")));
    }
}

class Stuff {
    public static void main(String[] args) {
        System.out.println("Algo");
    }
}
