package org.example.composite;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

class GraphicObject {
    protected String name = "Group";

    public GraphicObject() {
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String color;
    public List<GraphicObject> children = new ArrayList<>();

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        print(sb, 0);
        return sb.toString();
    }

    private void print(StringBuilder sb, int depth) {
        sb.append(String.join("", Collections.nCopies(depth, "*")))
                .append(depth > 0 ? " " : "")
                .append((color == null || color.isEmpty()) ? "" : color + " ")
                .append(getName())
                .append(System.lineSeparator());
        for (GraphicObject child : children)
            child.print(sb, depth + 1);
    }

}

class Circle extends GraphicObject {
    public Circle(String color) {
        name = "Circle";
        this.color = color;
    }
}

class Square extends GraphicObject {
    public Square(String color) {
        name = "Square";
        this.color = color;
    }
}

// Can instantiete GraphicObject becouse acts as grouping effectively
public class DemoComposite {
    public static void main(String[] args) {
        GraphicObject drawing = new GraphicObject();
        drawing.setName("My Drawing");
        drawing.children.add(new Circle("Red"));
        drawing.children.add(new Square("Blue"));

        // Can be treated in both singular manner as
        // Scalar objects or as collections of objects
        GraphicObject group = new GraphicObject();
        group.children.add(new Circle("Yellow"));
        group.children.add(new Square("Green"));
        drawing.children.add(group);

        System.out.println(drawing.toString());
    }
}
