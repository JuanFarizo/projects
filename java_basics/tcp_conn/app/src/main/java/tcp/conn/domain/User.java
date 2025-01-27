package tcp.conn.domain;

import java.util.UUID;

public class User {
    private final UUID id;
    private final String username;
    private final String address;
    
    public User(String username, String address) {
        this.id = UUID.randomUUID();
        this.username = username;
        this.address = address;
    }

    public UUID getUuid() {
        return id;
    }

    public String getUsername() {
        return username;
    }

    public String getAddress() {
        return address;
    }



    public UUID getId() {
        return id;
    }

}
