package demo;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

public class Repo {
    private final List<Person> people = new ArrayList<>();

    public void save(Person person) {
        people.add(person);
    }

    public Optional<Person> findByName(String name) {
        return people.stream().filter(p -> p.getName().equals(name)).findFirst();
    }

    public List<Person> findAll() {
        return List.copyOf(people);
    }
}
