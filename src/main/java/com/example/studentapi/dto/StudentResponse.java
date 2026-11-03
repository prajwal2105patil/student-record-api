package com.example.studentapi.dto;

import com.example.studentapi.model.Student;

public record StudentResponse(Long id, String usn, String name, String department, Integer semester) {

    public static StudentResponse from(Student s) {
        return new StudentResponse(s.getId(), s.getUsn(), s.getName(), s.getDepartment(), s.getSemester());
    }
}
