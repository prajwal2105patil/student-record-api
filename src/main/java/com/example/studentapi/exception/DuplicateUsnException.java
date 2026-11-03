package com.example.studentapi.exception;

public class DuplicateUsnException extends RuntimeException {

    public DuplicateUsnException(String usn) {
        super("A student with USN " + usn + " already exists");
    }
}
