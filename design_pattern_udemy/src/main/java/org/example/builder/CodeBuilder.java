package org.example.builder;

import java.util.ArrayList;
import java.util.List;

public class CodeBuilder {
    class Field {
        public String type;
        public String name;

        public Field(String name, String type) {
            this.name = name;
            this.type = type;
        }
    }

    private String className;
    private List<Field> fields;

    public CodeBuilder(String className) {
        this.className = className;
        this.fields = new ArrayList<Field>();
    }

    public CodeBuilder addField(String name, String type) {
        this.fields.add(new Field(name, type));
        return this;
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        sb.append("public class " + className);
        sb.append(System.lineSeparator());
        sb.append("{" + System.lineSeparator());
        fields.forEach(f -> {
            sb.append(" public " + f.type + " " + f.name + ";");
            sb.append(System.lineSeparator());
        });
        sb.append("}");
        return sb.toString();
    }

    public class Person {
        public String name;
        public int age;
    }

    public static void main(String[] args) {
        CodeBuilder cb = new CodeBuilder("Person")
                .addField("name", "String")
                .addField("age", "int");

        System.out.println(cb);
    }
}
