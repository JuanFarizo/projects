package org.example.flyweight;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.Function;

class User {
    @SuppressWarnings("unused")
    private String fullName;

    public User(String fullName) {
        this.fullName = fullName;
    }

}

class UserFlyweight {
    static List<String> strings = new ArrayList<>();
    @SuppressWarnings("unused")
    private int[] names;

    public UserFlyweight(String fullname) {
        // Utility function
        Function<String, Integer> getOrAdd = (String s) -> {
            int idx = strings.indexOf(s);
            if (idx != -1) {
                return idx;
            } else {
                strings.add(s);
                return strings.size() - 1;
            }
        };

        names = Arrays.stream(fullname.split(" "))
                .mapToInt(s -> getOrAdd.apply(s))
                .toArray();
    }
}

public class FlightweightDemo {
    @SuppressWarnings("unused")
    public static void main(String[] args) {
        UserFlyweight user = new UserFlyweight("Jhon Smith");
        UserFlyweight user2 = new UserFlyweight("Jane Smith");
        System.out.println("Stope here");
    }
}
