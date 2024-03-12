package com.simpleapi.example;

import java.io.IOException;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

import com.simpleapi.example.grpcserviceimpl.GprcSchoolServiceImpl;
import com.simpleapi.example.model.entity.Student;
import com.simpleapi.example.repository.StudentRepository;

import io.grpc.Server;
import io.grpc.ServerBuilder;

@SpringBootApplication
public class ExampleApplication {

	@Autowired
	private StudentRepository repository;

	public static void main(String[] args) throws IOException, InterruptedException {
		SpringApplication.run(ExampleApplication.class, args);
	}

	@Bean
	CommandLineRunner commandLineRunner() {
		return arg -> {
			repository.save(new Student("Juan Manuel", 10F));
			repository.save(new Student("Pedro Maldonado", 9.5F));
			repository.save(new Student("Mayra Delfrade", 8.80F));
			Server server = ServerBuilder
					.forPort(9090)
					.addService(new GprcSchoolServiceImpl()).build();

			server.start();
			server.awaitTermination();

		};
	}

}
