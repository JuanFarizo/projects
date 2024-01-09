package com.websocket.chatupgrade.controller;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;

import com.websocket.chatupgrade.chat.ChatMessage;
import com.websocket.chatupgrade.chat.ChatMessageService;
import com.websocket.chatupgrade.chat.ChatNotification;

import lombok.RequiredArgsConstructor;

@Controller
@RequiredArgsConstructor
public class ChatController {
    private final SimpMessagingTemplate template; // Allows to send an object or message to a queue
    private final ChatMessageService chatMessageService;

    @MessageMapping("/chat")
    public void processMessage(
            @Payload ChatMessage message) {
        ChatMessage saveMsg = chatMessageService.save(message);
        template.convertAndSendToUser(
                message.getRecipientId(),
                "/queue/messages",
                ChatNotification.builder()
                        .id(saveMsg.getId())
                        .senderId(saveMsg.getSenderId())
                        .recipientId(saveMsg.getRecipientId())
                        .content(saveMsg.getContent())
                        .build());

    }

    @GetMapping("/messages/{senderId}/{recipientId}")
    public ResponseEntity<List<ChatMessage>> findChatMessages(
            @PathVariable("senderId") String senderId,
            @PathVariable("recipientId") String recipientId) {
        return ResponseEntity.ok(chatMessageService.findChatMessages(senderId, recipientId));
    }

}
