-- ============================================================
-- MiniHRM Database Schema
-- Version  : 1.0
-- Created  : 2026-02-23
-- Author   : <Your Name>
-- Desc     : Create core tables: Departments, Positions, Employees
-- ============================================================

USE master;
GO

-- Tạo database nếu chưa có
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'MiniHRM')
BEGIN
    CREATE DATABASE MiniHRM;
    PRINT 'Database MiniHRM created.';
END
GO

USE MiniHRM;
GO

-- ============================================================
-- STEP 1: Departments (không có ManagerId FK trước)
-- ============================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Departments')
BEGIN
    CREATE TABLE Departments (
        Id          INT             PRIMARY KEY IDENTITY(1,1),
        Code        VARCHAR(20)     NOT NULL,
        Name        NVARCHAR(100)   NOT NULL,
        ManagerId   INT             NULL,       -- FK add sau (circular ref với Employees)
        IsActive    BIT             NOT NULL    DEFAULT 1,

        CreatedAt   DATETIME2       NOT NULL    DEFAULT GETUTCDATE(),
        CreatedBy   INT             NULL,
        UpdatedAt   DATETIME2       NULL,
        UpdatedBy   INT             NULL,

        CONSTRAINT UQ_Departments_Code UNIQUE (Code)
    );
    PRINT 'Table Departments created.';
END
GO

-- ============================================================
-- STEP 2: Positions
-- ============================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Positions')
BEGIN
    CREATE TABLE Positions (
        Id          INT             PRIMARY KEY IDENTITY(1,1),
        Code        VARCHAR(20)     NOT NULL,
        Title       NVARCHAR(100)   NOT NULL,
        Level       TINYINT         NOT NULL,   -- 1=Junior 2=Mid 3=Senior 4=Lead
        IsActive    BIT             NOT NULL    DEFAULT 1,

        CreatedAt   DATETIME2       NOT NULL    DEFAULT GETUTCDATE(),
        CreatedBy   INT             NULL,
        UpdatedAt   DATETIME2       NULL,
        UpdatedBy   INT             NULL,

        CONSTRAINT UQ_Positions_Code UNIQUE (Code)
    );
    PRINT 'Table Positions created.';
END
GO

-- ============================================================
-- STEP 3: Employees
-- ============================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Employees')
BEGIN
    CREATE TABLE Employees (
        Id              INT             PRIMARY KEY IDENTITY(1,1),
        EmployeeCode    VARCHAR(20)     NOT NULL,
        FirstName       NVARCHAR(50)    NOT NULL,
        LastName        NVARCHAR(50)    NOT NULL,
        FullName        AS (LastName + N' ' + FirstName) PERSISTED,
        Email           VARCHAR(150)    NOT NULL,
        Phone           VARCHAR(20)     NULL,
        DateOfBirth     DATE            NULL,
        Gender          TINYINT         NOT NULL    DEFAULT 0, -- 0=Other 1=Male 2=Female
        AvatarUrl       VARCHAR(500)    NULL,

        DepartmentId    INT             NOT NULL,
        PositionId      INT             NOT NULL,

        HireDate        DATE            NOT NULL,
        TerminationDate DATE            NULL,
        Status          TINYINT         NOT NULL    DEFAULT 1, -- 1=Active 0=Inactive 2=OnLeave
        IsActive        BIT             NOT NULL    DEFAULT 1,

        CreatedAt       DATETIME2       NOT NULL    DEFAULT GETUTCDATE(),
        CreatedBy       INT             NULL,
        UpdatedAt       DATETIME2       NULL,
        UpdatedBy       INT             NULL,

        CONSTRAINT UQ_Employees_Code    UNIQUE (EmployeeCode),
        CONSTRAINT UQ_Employees_Email   UNIQUE (Email),
        CONSTRAINT FK_Employees_Department
            FOREIGN KEY (DepartmentId)  REFERENCES Departments(Id),
        CONSTRAINT FK_Employees_Position
            FOREIGN KEY (PositionId)    REFERENCES Positions(Id)
    );
    PRINT 'Table Employees created.';
END
GO

-- ============================================================
-- STEP 4: Add ManagerId FK sau khi Employees đã tồn tại
-- ============================================================
IF NOT EXISTS (
    SELECT * FROM sys.foreign_keys
    WHERE name = 'FK_Departments_Manager'
)
BEGIN
    ALTER TABLE Departments
        ADD CONSTRAINT FK_Departments_Manager
        FOREIGN KEY (ManagerId) REFERENCES Employees(Id);
    PRINT 'FK FK_Departments_Manager added.';
END
GO

-- ============================================================
-- STEP 5: Indexes
-- ============================================================
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Employees_DepartmentId')
    CREATE INDEX IX_Employees_DepartmentId ON Employees (DepartmentId);

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Employees_PositionId')
    CREATE INDEX IX_Employees_PositionId   ON Employees (PositionId);

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Employees_Status')
    CREATE INDEX IX_Employees_Status       ON Employees (Status) WHERE IsActive = 1;

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Employees_FullName')
    CREATE INDEX IX_Employees_FullName     ON Employees (FullName);

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Departments_ManagerId')
    CREATE INDEX IX_Departments_ManagerId  ON Departments (ManagerId);

PRINT 'All indexes created.';
GO

PRINT '========================================';
PRINT 'MiniHRM schema setup completed successfully.';
PRINT '========================================';
GO

/*
## Chạy script trên SQL Server

Mở **SQL Server Management Studio (SSMS)** hoặc dùng thẳng VS 2026:

**Cách 1 — SSMS:**
1. Mở SSMS → connect tới SQL Server local
2. **File → Open → File** → chọn file `01_create_tables.sql`
3. Nhấn **F5** để chạy
4. Kiểm tra tab **Messages** phía dưới — phải thấy đủ các dòng `PRINT` như:
```
Database MiniHRM created.
Table Departments created.
Table Positions created.
Table Employees created.
FK FK_Departments_Manager added.
All indexes created.
========================================
MiniHRM schema setup completed successfully.
========================================
*/