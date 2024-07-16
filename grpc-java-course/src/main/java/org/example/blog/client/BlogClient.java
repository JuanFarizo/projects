package org.example.blog.client;

import com.proto.blog.Blog;
import com.proto.blog.BlogId;
import com.proto.blog.BlogServiceGrpc;
import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.grpc.StatusRuntimeException;

public class BlogClient {
    private static BlogId createBlog(BlogServiceGrpc.BlogServiceBlockingStub stub) {
        try {
            BlogId createResponse = stub.createBlog(
                    Blog.newBuilder()
                            .setAuthor("pepe")
                            .setTitle("como consumir falopa")
                            .setContent("la tomas y ya esta")
                            .build());
            System.out.println("Blog created: " + createResponse.getId());
            return createResponse;
        } catch (StatusRuntimeException e) {
            System.out.println("Error creating blog");
            e.printStackTrace();
            return null;
        }
    }

    private static void updateBlog(BlogServiceGrpc.BlogServiceBlockingStub stub,
            BlogId blogId) {
        try {
            Blog newBlog = Blog.newBuilder()
                    .setId(blogId.getId())
                    .setAuthor("farineitor")
                    .setTitle("how to do not that")
                    .setContent("just don't do it man")
                    .build();
            stub.updateBlog(newBlog);
            System.out.println("Blog updated " + newBlog);
        } catch (StatusRuntimeException e) {
            System.out.println("Blog can not be updated: " + blogId.getId());
            e.printStackTrace();
        }
    }

    private static void readBlog(BlogServiceGrpc.BlogServiceBlockingStub stub,
            BlogId blogId) {
        try {
            Blog readResponse = stub.readBlog(blogId);
            System.out.println("Blog read: " + readResponse);
        } catch (StatusRuntimeException e) {
            System.out.println(" Couldn't read the blog");
            e.printStackTrace();
        }
    }

    private static void run(ManagedChannel channel) {
        BlogServiceGrpc.BlogServiceBlockingStub stub = BlogServiceGrpc.newBlockingStub(
                channel);

        BlogId blogId = createBlog(stub);
        if (blogId == null)
            return;

        readBlog(stub, blogId);
        updateBlog(stub, blogId);

    }

    public static void main(String[] args) throws InterruptedException {
        // Channels are objects that will create the TCP connection between the client
        // and the server
        ManagedChannel channel = ManagedChannelBuilder.forAddress("localhost", 50051)
                .usePlaintext().build();

        run(channel);

        System.out.println("Shutting down");
        channel.shutdown();
    }
}