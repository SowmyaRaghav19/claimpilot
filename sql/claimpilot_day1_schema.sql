-- ClaimPilot - Day 1: tables and sample data for Azure SQL (free offer)
-- Run in SSMS against the ClaimPilotDB database. All data is invented for the demo.

-- 1. Tables ---------------------------------------------------------------

CREATE TABLE PolicyHolders (
    CustomerId   VARCHAR(20)  NOT NULL PRIMARY KEY,
    Name         NVARCHAR(100) NOT NULL,
    Email        NVARCHAR(200) NOT NULL
);

CREATE TABLE Policies (
    PolicyId     VARCHAR(30)   NOT NULL PRIMARY KEY,
    CustomerId   VARCHAR(20)   NOT NULL REFERENCES PolicyHolders(CustomerId),
    PlanName     NVARCHAR(100) NOT NULL,
    SumInsured   DECIMAL(12,2) NOT NULL,
    StartDate    DATE          NOT NULL,
    EndDate      DATE          NOT NULL,
    Status       VARCHAR(20)   NOT NULL   -- Active / Lapsed
);

CREATE TABLE PolicyRules (
    RuleId       INT IDENTITY(1,1) PRIMARY KEY,
    PolicyId     VARCHAR(30)   NOT NULL REFERENCES Policies(PolicyId),
    RuleType     VARCHAR(30)   NOT NULL,  -- WaitingPeriod / SubLimit / Exclusion
    RuleKey      NVARCHAR(100) NOT NULL,  -- e.g. RoomRentPerDay, Cataract, PreExisting
    RuleValue    NVARCHAR(100) NOT NULL   -- e.g. 5000, 24 months, Not covered
);

CREATE TABLE ClaimsLedger (
    ClaimId        VARCHAR(20)   NOT NULL PRIMARY KEY,
    PolicyId       VARCHAR(30)   NOT NULL REFERENCES Policies(PolicyId),
    ClaimDate      DATE          NOT NULL,
    ApprovedAmount DECIMAL(12,2) NOT NULL,
    Status         VARCHAR(20)   NOT NULL  -- Approved / Rejected / Escalated
);

-- 2. Sample data ----------------------------------------------------------

INSERT INTO PolicyHolders (CustomerId, Name, Email) VALUES
('CUST-201', N'Arun Kumar',   N'arun.demo@example.com'),
('CUST-202', N'Meena Ravi',   N'meena.demo@example.com'),
('CUST-203', N'Karthik Iyer', N'karthik.demo@example.com');

INSERT INTO Policies (PolicyId, CustomerId, PlanName, SumInsured, StartDate, EndDate, Status) VALUES
('POL-HEALTH-71', 'CUST-201', N'Family Health Silver', 300000, '2025-04-01', '2026-03-31', 'Lapsed'),
('POL-HEALTH-72', 'CUST-202', N'Family Health Gold',   500000, '2026-01-01', '2026-12-31', 'Active'),
('POL-HEALTH-73', 'CUST-203', N'Individual Basic',     200000, '2026-08-15', '2027-08-14', 'Active');

INSERT INTO PolicyRules (PolicyId, RuleType, RuleKey, RuleValue) VALUES
('POL-HEALTH-72', 'SubLimit',      N'RoomRentPerDay', N'5000'),
('POL-HEALTH-72', 'WaitingPeriod', N'PreExisting',    N'24 months'),
('POL-HEALTH-72', 'Exclusion',     N'Cosmetic',       N'Not covered'),
('POL-HEALTH-73', 'SubLimit',      N'RoomRentPerDay', N'3000'),
('POL-HEALTH-73', 'WaitingPeriod', N'InitialDays',    N'30 days'),
('POL-HEALTH-73', 'WaitingPeriod', N'Cataract',       N'24 months');

INSERT INTO ClaimsLedger (ClaimId, PolicyId, ClaimDate, ApprovedAmount, Status) VALUES
('CLM-0901', 'POL-HEALTH-72', '2026-03-10', 42000, 'Approved'),
('CLM-0902', 'POL-HEALTH-72', '2026-06-22', 18500, 'Approved'),
('CLM-0903', 'POL-HEALTH-73', '2026-09-01',     0, 'Rejected');

-- 3. Test the query the MCP tool will use ---------------------------------

DECLARE @policyId VARCHAR(30) = 'POL-HEALTH-72';

SELECT p.PolicyId,
       p.SumInsured,
       p.SumInsured - ISNULL(SUM(c.ApprovedAmount), 0) AS RemainingSumInsured
FROM Policies p
LEFT JOIN ClaimsLedger c
  ON c.PolicyId = p.PolicyId
  AND c.Status = 'Approved'
  AND c.ClaimDate >= p.StartDate
WHERE p.PolicyId = @policyId
GROUP BY p.PolicyId, p.SumInsured;
-- Expected: RemainingSumInsured = 439500.00
---------------------------

----CREATE VIEW vw_PolicyRulesText AS
----SELECT r.RuleId, p.PolicyId, p.PlanName,
----       CONCAT(p.PlanName, ': ', r.RuleType, ' - ', r.RuleKey, ' = ', r.RuleValue) AS RuleText
----FROM PolicyRules r JOIN Policies p ON p.PolicyId = r.PolicyId;
----GO
----SELECT * FROM vw_PolicyRulesText;