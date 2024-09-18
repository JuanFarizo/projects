package com.farins;

import com.mongodb.ConnectionString;
import com.mongodb.MongoClientSettings;
import com.mongodb.ServerApi;
import com.mongodb.ServerApiVersion;
import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoIterable;

public class Main {
    static final String stringConn = "mongodb+srv://myAtlasDBUser:myatlas-001@myatlasclusteredu.iq76f.mongodb.net/?retryWrites=true&w=majority&appName=myAtlasClusterEDU";

    public static void main(String[] args) {
        var cs = new ConnectionString(stringConn);

        var settings = MongoClientSettings.builder()
                .applyConnectionString(cs)
                .serverApi(
                        ServerApi.builder()
                                .version(ServerApiVersion.V1)
                                .build()
                ).build();
        MongoIterable<String> dbNames;
        try (var mongoClient = MongoClients.create(settings)) {
            dbNames = mongoClient.listDatabaseNames();
            dbNames.forEach(System.out::println);
        }
    }
}