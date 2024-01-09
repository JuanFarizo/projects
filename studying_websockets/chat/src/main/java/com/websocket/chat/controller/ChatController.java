package com.websocket.chat.controller;

import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.handler.annotation.SendTo;
import org.springframework.messaging.simp.SimpMessageHeaderAccessor;
import org.springframework.stereotype.Controller;

import com.websocket.chat.domain.ChatMessage;

@Controller
public class ChatController {

    @MessageMapping("/chat.sendMessage") // Map the url to invoking this method
    @SendTo("/topic/public") // Where (topic o queue) to send the message
    public ChatMessage sendMessage(@Payload ChatMessage message) {
        return message;
    }

    @MessageMapping("/chat.addUser") // Map the url to invoking this method
    @SendTo("/topic/public") // Where (topic o queue) to send the message
    public ChatMessage user(
            @Payload ChatMessage message,
            SimpMessageHeaderAccessor headerAccessor) {
        // Add username in websocket session
        headerAccessor.getSessionAttributes().put("username", message.getSender());
        return message;
    }
}
