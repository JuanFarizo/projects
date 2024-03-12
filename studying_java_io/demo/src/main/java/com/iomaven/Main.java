package com.iomaven;

import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Mode;

public class Main {
    private static final String FILE_NAME = "src/main/java/com/iomaven/resources/fileCreated.txt";

    public static void main(String[] args) throws Exception {
        org.openjdk.jmh.Main.main(args);
        // File file = new File(FILE_NAME);
        // Path newFilePath = Paths.get(FILE_NAME);
        // Files.createFile(newFilePath);

        // try (FileOutputStream fileOutputStream = new FileOutputStream(FILE_NAME)) {
        // String writing = "algo";
        // fileOutputStream.write(writing.getBytes());
        //
        // } catch (Exception e) {
        // System.out.println("algo");
        // }
    }

    @Benchmark
    @BenchmarkMode(Mode.AverageTime)
    public void init() {

    }
}