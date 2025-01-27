package tcp.conn.domain;

import java.util.Date;

public class Message {
    private  Integer id;
    private String sender; 
    private String receiver; 
    private String message; 
    private Date timeStamp;

    public Message(
        Integer id, 
        String sender, 
        String receiver, 
        String message) 
    {
        this.id = id;
        this.sender = sender;
        this.receiver = receiver;
        this.message = message;
        this.timeStamp = new Date();
    }
}
