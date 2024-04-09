package org.example.facade;

import java.util.ArrayList;
import java.util.List;

class Buffer {
    private char[] characters;
    private int lineWidth;

    public Buffer(int lineHeight, int lineWidth) {
        this.characters = new char[lineWidth * lineHeight];
        this.lineWidth = lineWidth;
    }

    public char charAt(int x, int y) {
        return characters[y * lineWidth + x];
    }
}

class ViewPort {
    private final Buffer bf;
    private final int width;
    private final int height;
    private final int offsetX;
    private final int offsetY;

    public ViewPort(Buffer bf, int width, int height, int offsetX, int offsetY) {
        this.bf = bf;
        this.width = width;
        this.height = height;
        this.offsetX = offsetX;
        this.offsetY = offsetY;
    }

    public char charAy(int x, int y) {
        return bf.charAt(x + offsetX, y + offsetY);
    }
}

class Console {
    private List<ViewPort> viewports = new ArrayList<>();
    int width, height;

    public Console(int width, int height) {
        this.width = width;
        this.height = height;
    }

    public void addViewport(ViewPort vp) {
        viewports.add(vp);
    }

    public static Console newConsole(int width, int height) {
        Buffer buffer = new Buffer(width, height);
        ViewPort viewPort = new ViewPort(buffer, width, height, 0, 0);
        Console console = new Console(width, width);
        console.addViewport(viewPort);
        return console;
    }

    public void render() {
        for (int y = 0; y < height; ++y) {
            for (int i = 0; i < width; i++) {
                for (ViewPort viewport : viewports) {
                    System.out.println(viewport.charAy(i, y));
                }
            }
        }
    }
}

public class FacadeDemo {
    public static void main(String[] args) {
        Console console = Console.newConsole(20, 30);
        console.render();
    }
}
