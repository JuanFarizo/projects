package com.optimization;

import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import javax.imageio.ImageIO;

public class OptimizationLatency {
    public static final String SOURCE_FILE = "./demo/resources/many-flowers.jpg";
    public static final String DESTINATION_FILE = "./demo/resources/many-flowers-out.jpg";

    public static void main(String[] args) throws IOException {
        BufferedImage originalImage = ImageIO.read(new File(SOURCE_FILE));
        BufferedImage resultImage = new BufferedImage(originalImage.getWidth(), originalImage.getHeight(),
                BufferedImage.TYPE_INT_RGB);
        long startTime = System.currentTimeMillis();
        // recolorSingleThreaded(originalImage, resultImage);
        // recolorMultiThreads(originalImage, resultImage, 2);
        long endTime = System.currentTimeMillis();
        long duration = endTime - startTime;
        File outputFile = new File(DESTINATION_FILE);
        ImageIO.write(resultImage, "jpg", outputFile);
        System.out.println("Duration of the run " + duration);
    }

    public static void recolorMultiThreads(BufferedImage originalImage, BufferedImage resultImage,
            int numberOfThreads) {
        List<Thread> threads = new ArrayList<>();
        int widht = originalImage.getWidth();
        int height = originalImage.getHeight() / numberOfThreads;

        for (int i = 0; i < numberOfThreads; i++) {
            final int threadMultiplier = i;
            Thread thread = new Thread(() -> {
                int leftCorner = 0;
                int topCorner = height * threadMultiplier;
                recolorImage(originalImage, resultImage, leftCorner, topCorner, widht, height);
            });
            threads.add(thread);
        }
        for (Thread thread : threads) {
            thread.start();
        }
        for (Thread thread : threads) {
            try {
                thread.join();
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }
    }

    public static void recolorSingleThreaded(BufferedImage originalImage, BufferedImage resultImage) {
        recolorImage(originalImage, resultImage,
                0, 0,
                originalImage.getWidth(), originalImage.getHeight());
    }

    public static void recolorImage(BufferedImage originalImage, BufferedImage resultImage,
            int leftCorner, int topCorner, int width, int height) {
        for (int x = leftCorner; x < leftCorner + width && x < originalImage.getWidth(); x++) {
            for (int y = topCorner; y < topCorner + height && y < originalImage.getHeight(); y++) {
                recolorPixel(originalImage, resultImage, x, y);
            }
        }
    }

    public static void recolorPixel(BufferedImage originalImage, BufferedImage resultImage, int x, int y) {
        int rgb = originalImage.getRGB(x, y);
        int red = getRed(rgb);
        int green = getGreen(rgb);
        int blue = getBlue(rgb);

        int newRed;
        int newGren;
        int newBlue;
        if (isShadeOfGrat(red, green, blue)) {
            // Arbitrary values based on experience only for achive purple color (reducing
            // green)
            newRed = Math.min(255, red + 10);
            newGren = Math.max(0, green - 80);
            newBlue = Math.max(0, blue - 20);
        } else {
            newRed = red;
            newBlue = blue;
            newGren = green;
        }
        int newRGB = createRGBFromColors(newRed, newGren, newBlue);
        setRGB(resultImage, x, y, newRGB);
    }

    public static void setRGB(BufferedImage image, int x, int y, int rgb) {
        image.getRaster().setDataElements(x, y, image.getColorModel().getDataElements(rgb, null));
    }

    public static boolean isShadeOfGrat(int red, int green, int blue) {
        return Math.abs(red - green) < 30 &&
                Math.abs(red - blue) < 30 &&
                Math.abs(green - blue) < 30;
    }

    public static int createRGBFromColors(int red, int green, int blue) {
        int rgb = 0;
        rgb |= blue;
        rgb |= green << 8;
        rgb |= red << 16;

        rgb |= 0xFF000000;
        return rgb;
    }

    public static int getRed(int rgb) {
        return (rgb & 0X00FF0000) >> 16;
    }

    public static int getGreen(int rgb) {
        return (rgb & 0x0000FF00) >> 8;
    }

    public static int getBlue(int rgb) {
        return rgb & 0x000000FF;
    }
}
