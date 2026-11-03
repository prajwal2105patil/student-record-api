# Student Record Management API

**Author:** Mahantesh R. Patted (USN 23BTRCT066), B.Tech CSE, Jain (Deemed-to-be) University, Bengaluru

Implementation Assignment 1 (REST APIs using Spring Boot). The full test report with screenshots is in [`docs/Student-Record-API-Report.pdf`](docs/Student-Record-API-Report.pdf) (also `.docx`), and the raw generated evidence is in [`REPORT.md`](REPORT.md).

A Spring Boot REST API that stores student records (generated id, unique USN, name, department, semester 1–8) in an H2 database.

## Versions

| Component | Version |
|---|---|
| Java (target) | 17 (also runs on JDK 21) |
| Spring Boot | 3.5.0 (`spring-boot-starter-parent`) |
| Build tool | Maven 3.9+ |
| Database | H2 (version managed by Spring Boot) |
| Persistence | Spring Data JPA / Hibernate |

The project was generated with Spring Initializr (dependencies: Spring Web, Spring Data JPA, Validation, H2 Database).

## H2 mode: file-based

`spring.datasource.url=jdbc:h2:file:./data/studentdb;AUTO_SERVER=TRUE;WRITE_DELAY=0`

`WRITE_DELAY=0` makes H2 flush each commit to disk immediately, so records survive even a forced kill.

Data lives in `data/studentdb.mv.db`, relative to the folder you run the JAR from, and **survives restarts**. The startup seeder checks each USN before inserting, so restarting never duplicates the three sample students. To start fresh, stop the app and delete `data/`.

## Project layout

```
src/main/java/com/example/studentapi/
├── StudentApiApplication.java      entry point + "ready" startup log
├── controller/StudentController    HTTP only: routes, @Valid, status codes
├── service/StudentService          business rules, uniqueness, transactions, mutation logs
├── repository/StudentRepository    Spring Data JPA interface
├── model/Student                   JPA entity (unique constraint on usn)
├── dto/                            StudentRequest (validation), StudentResponse, ErrorResponse
├── exception/                      custom exceptions + GlobalExceptionHandler (JSON errors, WARN logs)
└── config/DataSeeder               CommandLineRunner, idempotent seed of 3 students
```

Every class uses constructor-based dependency injection; there is no field `@Autowired`.

## Build and run

```bash
mvn clean package
java -jar target/student-api-0.0.1-SNAPSHOT.jar
```

The API listens on `http://localhost:8080`.

On Windows you can instead double-click **`START-APP.bat`**: it finds JDK 17+ and Maven (downloading portable copies into `.tools\` if missing), builds the JAR and runs it in that window.

- **API test console:** `http://localhost:8080/api-console.html`, a small browser page used for the report screenshots. Pick a method, enter the URL and JSON body, press **Send**, and it shows the live status code, time, `Content-Type`/`Location` headers and the response body.
- H2 console: `http://localhost:8080/h2-console` (JDBC URL `jdbc:h2:file:./data/studentdb;AUTO_SERVER=TRUE`, user `sa`, empty password)
- Logs: console and `logs/student-api.log`

### One-command demo and report

**Windows:** double-click `RUN-ME.bat` (it runs `run-demo.ps1`). Nothing needs to be pre-installed: if no JDK 17+ is found it downloads a portable Temurin JDK 21 into `.tools\`, and if Maven isn't on PATH it downloads Maven 3.9.11 there too.

**Linux / macOS / Git Bash:**

```bash
./demo.sh
```

Both scripts build the JAR, starts it, runs every required scenario, runs an H2 query, restarts the app to show persistence, and writes **`REPORT.md`** with the requests, status codes, response bodies and log extracts. It deletes `data/` first so the evidence starts clean; pass `--keep-data` to keep existing records.

## Endpoints

| Method | Path | Success | Errors |
|---|---|---|---|
| POST | `/students` | 201 + `Location` header | 400 validation, 409 duplicate USN |
| GET | `/students` | 200 | none |
| GET | `/students?department=CSE` | 200 (case-insensitive) | none |
| GET | `/students/{id}` | 200 | 404, 400 if the id is not a number |
| PUT | `/students/{id}` | 200 | 400, 404 (never creates), 409 |
| DELETE | `/students/{id}` | 204 | 404 |

USNs and departments are trimmed and upper-cased before saving, so `1js23cs101` and `1JS23CS101` count as the same USN.

Error body format:

```json
{
  "timestamp": "2026-11-03T06:30:00.123Z",
  "status": 400,
  "error": "Bad Request",
  "message": "Validation failed for fields [semester]",
  "path": "/students",
  "fieldErrors": { "semester": "Semester must be between 1 and 8" }
}
```

## Sample requests (curl)

On Windows PowerShell, use `curl.exe` and put the JSON in a file (`-d "@body.json"`), or run these from Git Bash.

```bash
# Create (201)
curl -i -X POST http://localhost:8080/students -H "Content-Type: application/json" \
  -d '{"usn":"1JS23CS101","name":"Mahantesh R. Patted","department":"CSE","semester":5}'

# List all / filter (200)
curl -i http://localhost:8080/students
curl -i "http://localhost:8080/students?department=CSE"

# Get by id (200 / 404)
curl -i http://localhost:8080/students/4

# Duplicate USN (409)
curl -i -X POST http://localhost:8080/students -H "Content-Type: application/json" \
  -d '{"usn":"1JS23CS101","name":"Someone Else","department":"ISE","semester":3}'

# Invalid semester (400)
curl -i -X POST http://localhost:8080/students -H "Content-Type: application/json" \
  -d '{"usn":"1JS23CS102","name":"Test User","department":"CSE","semester":9}'

# Update (200)
curl -i -X PUT http://localhost:8080/students/4 -H "Content-Type: application/json" \
  -d '{"usn":"1JS23CS101","name":"Mahantesh R. Patted","department":"AIML","semester":6}'

# Delete (204), then lookup (404)
curl -i -X DELETE http://localhost:8080/students/4
curl -i http://localhost:8080/students/4
```

A Postman collection with the same requests and status assertions is in `postman/Student-API.postman_collection.json`.

## H2 query

Use the H2 console, or the H2 shell while the app is running:

```bash
java -cp ~/.m2/repository/com/h2database/h2/<version>/h2-<version>.jar org.h2.tools.Shell \
  -url "jdbc:h2:file:./data/studentdb;AUTO_SERVER=TRUE" -user sa \
  -sql "SELECT ID, USN, NAME, DEPARTMENT, SEMESTER FROM STUDENTS ORDER BY ID"
```

## Logging

The log pattern is `timestamp LEVEL [thread] class - message`, for example:

```
2026-11-03 12:05:41.512 INFO  [http-nio-8080-exec-2] c.e.studentapi.service.StudentService - Student created: id=4, usn=1JS23CS101
2026-11-03 12:05:41.611 WARN  [http-nio-8080-exec-3] c.e.s.exception.GlobalExceptionHandler - Request failed: POST /students -> 409 Conflict: A student with USN 1JS23CS101 already exists
```

Only ids, USNs and failure reasons are logged, never full student records or request bodies.
