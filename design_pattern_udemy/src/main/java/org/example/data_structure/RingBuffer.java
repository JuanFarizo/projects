package org.example.data_structure;

public class RingBuffer<T> {
    private static final int DEFAULT_CAPACITY = 8;
    private T[] data;
    private int capacity;
    private volatile int writeSequence;
    private volatile int readSequence;

    public RingBuffer(int capacity) {
        this.capacity = capacity < 1 ? DEFAULT_CAPACITY : capacity;
        this.data = (T[]) new Object[this.capacity];
        this.readSequence = 0;
        this.writeSequence = -1;
    }

    /**
     * Inserts an element into the buffer at the next available slot and returns
     * true on success. It returns false if the buffer can’t find an empty slot,
     * that is, we can’t overwrite unread values.
     * 
     * @param element to insert
     * @return true if it is inserted, false if isn't empty slot
     */
    public boolean offer(T element) {
        boolean isFull = this.isFull();
        if (!isFull) {
            this.data[++writeSequence % this.capacity] = element;
            return true;
        }
        return false;
    }

    /**
     * Retrieves and removes the next unread element. The poll operation doesn’t
     * remove the element but increments the read sequence.
     * 
     * @return The element
     */
    public T poll() {
        boolean isEmpty = this.isEmpty();
        if (!isEmpty) {
            T nextValue = this.data[this.readSequence % this.capacity];
            this.readSequence++;
            return nextValue;
        }
        return null;
    }

    /**
     * The buffer is full if the size of the buffer is equal to its capacity
     */
    private boolean isFull() {
        return writeSequence - readSequence + 1 == capacity;
    }

    /**
     * If the write sequence lags behind the read sequence, the buffer is empty
     */
    private boolean isEmpty() {
        return writeSequence < readSequence;
    }

    // The buffer returns a null value if it’s empty.

}
