package crudemo.crudemo.controller;

import java.util.List;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import crudemo.crudemo.entity.Student;

@RestController
@RequestMapping("/api")
public class StudentController {

    @GetMapping("/students")
    public List<Student> getMethodName() {
        return List.of(new Student("Pepe", "Trueno", "Pepetrueno@hotmail.com"));
    }

}
