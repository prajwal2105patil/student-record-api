package com.example.studentapi.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

@Entity
@Table(name = "students", uniqueConstraints = @UniqueConstraint(name = "uk_students_usn", columnNames = "usn"))
public class Student {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 20)
    private String usn;

    @Column(nullable = false, length = 100)
    private String name;

    @Column(nullable = false, length = 50)
    private String department;

    @Column(nullable = false)
    private Integer semester;

    protected Student() {
        // required by JPA
    }

    public Student(String usn, String name, String department, Integer semester) {
        this.usn = usn;
        this.name = name;
        this.department = department;
        this.semester = semester;
    }

    public Long getId() { return id; }
    public String getUsn() { return usn; }
    public String getName() { return name; }
    public String getDepartment() { return department; }
    public Integer getSemester() { return semester; }

    public void setUsn(String usn) { this.usn = usn; }
    public void setName(String name) { this.name = name; }
    public void setDepartment(String department) { this.department = department; }
    public void setSemester(Integer semester) { this.semester = semester; }
}
