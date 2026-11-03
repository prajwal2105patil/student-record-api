package com.example.studentapi.service;

import com.example.studentapi.dto.StudentRequest;
import com.example.studentapi.dto.StudentResponse;
import com.example.studentapi.exception.DuplicateUsnException;
import com.example.studentapi.exception.StudentNotFoundException;
import com.example.studentapi.model.Student;
import com.example.studentapi.repository.StudentRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Locale;

/**
 * Business rules live here: normalisation, USN uniqueness, "PUT never creates", and mutation logging.
 * The controller only translates HTTP to method calls; the repository only talks to H2.
 */
@Service
public class StudentService {

    private static final Logger log = LoggerFactory.getLogger(StudentService.class);

    private final StudentRepository repository;

    public StudentService(StudentRepository repository) {
        this.repository = repository;
    }

    @Transactional(readOnly = true)
    public List<StudentResponse> findAll(String department) {
        List<Student> students = (department == null || department.isBlank())
                ? repository.findAllByOrderByIdAsc()
                : repository.findByDepartmentIgnoreCaseOrderByIdAsc(department.trim());
        return students.stream().map(StudentResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public StudentResponse findById(Long id) {
        return StudentResponse.from(getOrThrow(id));
    }

    @Transactional
    public StudentResponse create(StudentRequest request) {
        String usn = normaliseUsn(request.usn());
        if (repository.existsByUsn(usn)) {
            throw new DuplicateUsnException(usn);
        }
        Student saved = saveOrConflict(new Student(
                usn, request.name().trim(), normaliseDepartment(request.department()), request.semester()), usn);
        log.info("Student created: id={}, usn={}", saved.getId(), saved.getUsn());
        return StudentResponse.from(saved);
    }

    @Transactional
    public StudentResponse update(Long id, StudentRequest request) {
        Student existing = getOrThrow(id); // 404 - PUT must never create a missing record
        String usn = normaliseUsn(request.usn());
        if (repository.existsByUsnAndIdNot(usn, id)) {
            throw new DuplicateUsnException(usn);
        }
        existing.setUsn(usn);
        existing.setName(request.name().trim());
        existing.setDepartment(normaliseDepartment(request.department()));
        existing.setSemester(request.semester());
        Student saved = saveOrConflict(existing, usn);
        log.info("Student updated: id={}, usn={}", saved.getId(), saved.getUsn());
        return StudentResponse.from(saved);
    }

    @Transactional
    public void delete(Long id) {
        Student existing = getOrThrow(id);
        repository.delete(existing);
        log.info("Student deleted: id={}, usn={}", id, existing.getUsn());
    }

    private Student getOrThrow(Long id) {
        return repository.findById(id).orElseThrow(() -> new StudentNotFoundException(id));
    }

    /** The unique constraint is the final guard if two requests race past the existsBy check. */
    private Student saveOrConflict(Student student, String usn) {
        try {
            return repository.saveAndFlush(student);
        } catch (DataIntegrityViolationException e) {
            throw new DuplicateUsnException(usn);
        }
    }

    private static String normaliseUsn(String usn) {
        return usn.trim().toUpperCase(Locale.ROOT);
    }

    private static String normaliseDepartment(String department) {
        return department.trim().toUpperCase(Locale.ROOT);
    }
}
