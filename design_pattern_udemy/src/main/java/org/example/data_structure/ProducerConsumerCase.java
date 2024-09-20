package org.example.data_structure;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Use of a ring/circular buffer for exchanging data between two
 * or more threads, which is an example of a synchronization problem called the
 * Producer-Consumer problem. In Java, we can solve the producer-consumer
 * problem in various ways using semaphores, bounded queues, ring buffers, etc.
 */
public class ProducerConsumerCase {
    private static int RING_BUFFER_SIZE = 8;
    private static RingBuffer<String> buffer = new RingBuffer<>(RING_BUFFER_SIZE);
    private static List<String> items = List.of("One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight");

    public static void main(String[] args) {
        ExecutorService executor = Executors.newFixedThreadPool(2);
        executor.execute(new Thread(new Producer(), "Producer Thread"));
        executor.execute(new Thread(new Consumer(), "Consumer Thread"));
        executor.shutdown();
    }

    public static class Producer implements Runnable {
        @Override
        public void run() {
            int i = 0;
            while (true) {
                if (buffer.offer(items.get(i))) {
                    System.out.println("Produced: " + items.get(i));
                    i = i == RING_BUFFER_SIZE - 1 ? 0 : ++i;
                }
            }
        }
    }

    public static class Consumer implements Runnable {
        @Override
        public void run() {
            while (true) {
                String item = buffer.poll();
                if (item != null) {
                    System.out.println("Consumed: " + item);
                }
            }
        }
    }
}
