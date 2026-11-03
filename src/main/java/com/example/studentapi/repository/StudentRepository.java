package com.example.studentapi.repository;

import com.example.studentapi.model.Student;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface StudentRepository extends JpaRepository<Student, Long> {

    boolean existsByUsn(String usn);

    boolean existsByUsnAndIdNot(String usn, Long id);

    List<Student> findByDepartmentIgnoreCaseOrderByIdAsc(String department);

    List<Student> findAllByOrderByIdAsc();
}
