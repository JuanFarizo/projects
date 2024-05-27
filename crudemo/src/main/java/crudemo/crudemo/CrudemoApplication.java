package crudemo.crudemo;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

import crudemo.crudemo.entity.Student;
import crudemo.crudemo.entity.StudentDAO;

@SpringBootApplication
public class CrudemoApplication {

	public static void main(String[] args) {
		SpringApplication.run(CrudemoApplication.class, args);
	}

	@Bean
	public CommandLineRunner commandLineRunner(StudentDAO studentDAO) {
		return runner -> {
			System.out.println("Hellow World");
			// Student student = new Student("Pepe", "Trueno", "pepe@trueno.com");
			// studentDAO.save(student);
			// System.out.println("Saved student. Generated id:" + student.getId());

			// List<Student> resuList = studentDAO.findByLastName("Trueno");
			// for (Student s : resuList) {
			// System.out.println(s);
			// }

			// Student student = studentDAO.findById(1);
			// student.setFirstName("Grillo");
			// studentDAO.update(student);

		};
	}
}
