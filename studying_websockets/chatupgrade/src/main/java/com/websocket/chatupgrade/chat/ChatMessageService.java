package com.websocket.chatupgrade.chat;

import java.util.ArrayList;
import java.util.List;

import org.springframework.stereotype.Service;

import com.websocket.chatupgrade.chatroom.ChatRoomService;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class ChatMessageService {
    private final ChatMessageRepository chatMessageRepository;
    private final ChatRoomService chatRoomService;

    public ChatMessage save(ChatMessage message) {
        String chatId = chatRoomService.getChatRoomId(message.getSenderId(), message.getRecipientId(), true)
                .orElseThrow(() -> new IllegalStateException("Chat room can not be created"));
        message.setChatId(chatId);
        chatMessageRepository.save(message);
        return message;
    }

    public List<ChatMessage> findChatMessages(String senderId, String recipientId) {
        var chatId = chatRoomService.getChatRoomId(senderId, recipientId, false);
        return chatId.map(chatMessageRepository::findByChatId).orElse(new ArrayList<>());
    }

}
