package org.example.open_close_principle;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.stream.Collectors;

import org.javatuples.Triplet;

public class InversionControl {

    enum Relationship {
        PARENT,
        CHILD,
        SIBLING
    }

    static class Person {
        public String name;

        public Person(String name) {
            this.name = name;
        }
    }

    interface RelationShipBrowser {
        List<Person> findAllchildrenOf(String name);
    }

    static class Relationships implements RelationShipBrowser { // Low-Level
        private List<Triplet<Person, Relationship, Person>> relations = new ArrayList<>();

        public void addParentAndChild(Person parent, Person child) {
            relations.add(new Triplet<>(parent, Relationship.PARENT, child));
            relations.add(new Triplet<>(child, Relationship.CHILD, parent));
        }

        public List<Triplet<Person, Relationship, Person>> getRelations() {
            return relations;
        }

        @Override
        public List<Person> findAllchildrenOf(String name) { // Thanks of this we do not break dependency inversion
            return relations.stream()
                    .filter(x -> Objects.equals(x.getValue0().name, name) && x.getValue1() == Relationship.PARENT)
                    .map(Triplet::getValue2)
                    .collect(Collectors.toList());
        }

    }

    static class Research { // High-level
        // public Research(Relationships relationships) { // takes a low level module as dependency (not good)
        //     List<Triplet<Person, Relationship, Person>> relations = relationships.getRelations();
        //     relations.stream()
        //             .filter(x -> x.getValue0().name.equals("John") && x.getValue1() == Relationship.PARENT)
        //             .forEach(ch -> System.out.println(
        //                     "John has a child called " + ch.getValue2().name));
        // }

        public Research(RelationShipBrowser browser) {
            List<Person> children = browser.findAllchildrenOf("John");
            children.forEach(c -> System.out.println("Children names is: " + c.name));
        }
    }

    public static void main(String[] args) {
        Person parent = new Person("John");
        Person child1 = new Person("Chris");
        Person child2 = new Person("Matt");

        Relationships relationships = new Relationships();
        relationships.addParentAndChild(parent, child1);
        relationships.addParentAndChild(parent, child2);

        new Research(relationships);
    }

}
