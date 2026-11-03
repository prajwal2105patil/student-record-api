package com.example.studentapi.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/** Request body for POST and PUT. The id is never accepted from the client. */
public record StudentRequest(
        @NotBlank(message = "USN must not be blank")
        @Size(max = 20, message = "USN must be at most 20 characters")
        String usn,

        @NotBlank(message = "Name must not be blank")
        @Size(max = 100, message = "Name must be at most 100 characters")
        String name,

        @NotBlank(message = "Department must not be blank")
        @Size(max = 50, message = "Department must be at most 50 characters")
        String department,

        @NotNull(message = "Semester is required")
        @Min(value = 1, message = "Semester must be between 1 and 8")
        @Max(value = 8, message = "Semester must be between 1 and 8")
        Integer semester
) {
}
