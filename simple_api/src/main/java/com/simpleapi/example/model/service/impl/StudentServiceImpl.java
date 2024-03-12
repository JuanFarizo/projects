package com.simpleapi.example.model.service.impl;

import java.util.List;

import org.springframework.stereotype.Service;

import com.simpleapi.example.model.entity.Student;
import com.simpleapi.example.model.service.StudentService;
import com.simpleapi.example.repository.StudentRepository;

@Service
public class StudentServiceImpl implements StudentService {

    private final StudentRepository repository;

    public StudentServiceImpl(StudentRepository repository) {
        this.repository = repository;
    }

    @Override
    public List<Student> allStudents() {
        return repository.findAll();
    }

}
