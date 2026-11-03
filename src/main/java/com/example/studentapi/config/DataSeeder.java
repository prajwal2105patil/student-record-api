package com.example.studentapi.config;

import com.example.studentapi.model.Student;
import com.example.studentapi.repository.StudentRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/** Inserts three sample students on startup. Idempotent: a seed is skipped if its USN already exists. */
@Component
public class DataSeeder implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(DataSeeder.class);

    private static final List<Student> SEEDS = List.of(
            new Student("1JS23CS001", "Aarav Sharma", "CSE", 5),
            new Student("1JS23EC014", "Diya Nair", "ECE", 3),
            new Student("1JS23CS027", "Rohan Gupta", "CSE", 7)
    );

    private final StudentRepository repository;

    public DataSeeder(StudentRepository repository) {
        this.repository = repository;
    }

    @Override
    @Transactional
    public void run(String... args) {
        int inserted = 0;
        int skipped = 0;
        for (Student seed : SEEDS) {
            if (repository.existsByUsn(seed.getUsn())) {
                skipped++;
            } else {
                repository.save(new Student(seed.getUsn(), seed.getName(), seed.getDepartment(), seed.getSemester()));
                inserted++;
            }
        }
        log.info("Seed data: inserted={}, skipped(already present)={}, total students now={}",
                inserted, skipped, repository.count());
    }
}
