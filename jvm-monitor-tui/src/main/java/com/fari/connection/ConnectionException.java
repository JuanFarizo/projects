package com.fari.connection;

public class ConnectionException extends RuntimeException {

    public ConnectionException(String message, Throwable cause) {
        super(message, cause);
    }

    public ConnectionException(String message) {
        super(message);
    }
}
