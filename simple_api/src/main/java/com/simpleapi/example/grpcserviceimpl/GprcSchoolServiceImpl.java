package com.simpleapi.example.grpcserviceimpl;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;

import com.simpleapi.example.model.entity.Student;
import com.simpleapi.example.model.service.StudentService;
import com.student.service.grpc.Empty;
import com.student.service.grpc.ListStudent;
import com.student.service.grpc.StudentServiceGrpc.StudentServiceImplBase;

import io.grpc.stub.StreamObserver;
import net.devh.boot.grpc.server.service.GrpcService;

@GrpcService
public class GprcSchoolServiceImpl extends StudentServiceImplBase {

    @Autowired
    private StudentService studentService;

    @Override
    public void allStudents(Empty request, StreamObserver<ListStudent> responseObserver) {
        List<Student> students = studentService.allStudents();

        var listToReturn = ListStudent.newBuilder();
        students.forEach(s -> {
            com.student.service.grpc.Student student = com.student.service.grpc.Student.newBuilder()
                    .setId(s.getId())
                    .setName(s.getName())
                    .setCalification(s.getCalification())
                    .build();
            listToReturn.addStudents(student);
        });
        responseObserver.onNext(listToReturn.build());
        responseObserver.onCompleted();
    }

}
