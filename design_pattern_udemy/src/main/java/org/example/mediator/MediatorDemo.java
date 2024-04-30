package org.example.mediator;

import java.util.ArrayList;
import java.util.List;

class PersonMed {
    public String name;
    public ChatRoomMed room;
    private List<String> chatLog = new ArrayList<>();

    public PersonMed(String name) {
        this.name = name;
    }

    public void recieve(String sender, String message) {
        String s = sender + ":' " + message + "'";
        System.out.println("[" + name + "'s chat session] " + s);
        chatLog.add(s);
    }

    public void say(String message) {
        room.broadcast(name, message);
    }

    public void privateMessage(String who, String message) {
        room.message(name, who, message);
    }
}

class ChatRoomMed {
    private List<PersonMed> people = new ArrayList<>();

    public void join(PersonMed p) {
        String joinMsg = p.name + " joins the room";
        broadcast("room", joinMsg);

        p.room = this;
        people.add(p);
    }

    public void message(String source, String destination, String message) {
        people.stream()
                .filter(p -> p.name.equals(destination))
                .findFirst()
                .ifPresent(person -> person.recieve(source, message));
    }

    public void broadcast(String source, String message) {
        for (PersonMed p : people) {
            if (!p.name.equals(source)) {
                p.recieve(source, message);
            }
        }
    }
}

public class MediatorDemo {
    public static void main(String[] args) {
        ChatRoomMed chatRoom = new ChatRoomMed();
        PersonMed john = new PersonMed("John");
        PersonMed jane = new PersonMed("Jane");
        PersonMed simon = new PersonMed("Simon");

        chatRoom.join(john);
        chatRoom.join(jane);
        john.say("Hi room");
        jane.say("Hi john");

        chatRoom.join(simon);
        simon.say("Hi everyone");
        jane.privateMessage("Simon", "Hi Simon you are a pussy");

    }
}
