package com.example;

import java.util.List;

public class App {
    public static void main(String[] args) {
        Thread thread = new NewThread();
        Thread thread2 = new Thread(new Runnable() {
            @Override
            public void run() {
                System.out.println("Executing from a new thread");
            }
        });
        Runnable task = new Runnable(){
            @Override
            public void run() {
                System.out.println("Do Something");
            }
        };
        List<Runnable> tasks = List.of(new Runnable() {

            @Override
            public void run() {
                System.out.println("Hago falopa");
            }

        });
        MultiExecutor multiExecutor = new MultiExecutor(tasks);
        multiExecutor.executeAll();
    }

    private static class NewThread extends Thread {
        @Override
        public void run() {
            System.out.println("Running from mother thread: " + Thread.currentThread().getName());
        }
    }

    private static class MultiExecutor {
        // Add any necessary member variables here
        List<Runnable> tasks;

        /*
         * @param tasks to executed concurrently
         */
        public MultiExecutor(List<Runnable> tasks) {
            this.tasks = tasks;
        }

        /**
         * Starts and executes all the tasks concurrently
         */
        public void executeAll() {
            this.tasks.forEach(task -> {
                Thread thread = new Thread(task);
                thread.start();
            });
        }
    }
}
