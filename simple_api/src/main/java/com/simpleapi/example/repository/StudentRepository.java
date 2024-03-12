package com.simpleapi.example.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.simpleapi.example.model.entity.Student;

@Repository
public interface StudentRepository extends JpaRepository<Student, Long> {

}
