"""ClaimPilot SQL MCP server.

Exposes policy and claim-history data from Azure SQL (ClaimPilotDB) as MCP tools,
so both ClaimPilot agents (Foundry Intake Agent and .NET Adjudication Agent) can use them.
Policy wording and rule text come from the Foundry IQ knowledge base (claimpilot-kb), not from here.
"""
import datetime
import decimal
import os
import time

import pyodbc
from dotenv import load_dotenv
from mcp.server.mcpserver import MCPServer

load_dotenv()
CONN_STR = os.environ["SQL_CONNECTION_STRING"]

mcp = MCPServer("claimpilot-sql")


def _connect() -> pyodbc.Connection:
    """Open a connection. The free serverless database auto-pauses, so the first
    connection after a pause can take up to a minute while it wakes up."""
    for attempt in range(3):
        try:
            return pyodbc.connect(CONN_STR, timeout=60)
        except pyodbc.Error:
            if attempt == 2:
                raise
            time.sleep(10)


def _clean(value):
    """Make SQL values JSON-friendly."""
    if isinstance(value, decimal.Decimal):
        return float(value)
    if isinstance(value, (datetime.date, datetime.datetime)):
        return value.isoformat()
    return value


def _rows(cursor) -> list[dict]:
    cols = [c[0] for c in cursor.description]
    return [{k: _clean(v) for k, v in zip(cols, row)} for row in cursor.fetchall()]


@mcp.tool()
def get_policy(policy_id: str) -> dict:
    """Get a health insurance policy by its ID (for example POL-HEALTH-72).

    Returns the plan name, sum insured, start and end dates, status (Active or Lapsed),
    the policy holder's name and email, and the plan's rules (waiting periods,
    sub-limits and exclusions). Use this to confirm a policy exists and is active
    before assessing a claim. Returns found=false if the policy does not exist.
    """
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            """SELECT p.PolicyId, p.PlanName, p.SumInsured, p.StartDate, p.EndDate, p.Status,
                      h.CustomerId, h.Name AS HolderName, h.Email AS HolderEmail
               FROM dbo.Policies p
               JOIN dbo.PolicyHolders h ON h.CustomerId = p.CustomerId
               WHERE p.PolicyId = ?""",
            policy_id,
        )
        rows = _rows(cur)
        if not rows:
            return {"found": False, "policyId": policy_id}

        policy = rows[0]
        cur.execute(
            """SELECT RuleType, RuleKey, RuleValue
               FROM dbo.PolicyRules
               WHERE PolicyId = ?
               ORDER BY RuleType, RuleKey""",
            policy_id,
        )
        policy["rules"] = _rows(cur)
        policy["found"] = True
        return policy


@mcp.tool()
def get_claim_history(policy_id: str) -> dict:
    """Get past claims for a policy and the remaining sum insured for the current policy year.

    Returns every claim in the ledger (claim ID, date, approved amount, status) and
    remainingSumInsured = sum insured minus approved claims since the policy start date.
    Use this before deciding the payable amount for a new claim.
    """
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            """SELECT ClaimId, ClaimDate, ApprovedAmount, Status
               FROM dbo.ClaimsLedger
               WHERE PolicyId = ?
               ORDER BY ClaimDate""",
            policy_id,
        )
        claims = _rows(cur)

        cur.execute(
            """SELECT p.SumInsured,
                      p.SumInsured - ISNULL(SUM(c.ApprovedAmount), 0) AS RemainingSumInsured
               FROM dbo.Policies p
               LEFT JOIN dbo.ClaimsLedger c
                 ON c.PolicyId = p.PolicyId
                AND c.Status = 'Approved'
                AND c.ClaimDate >= p.StartDate
               WHERE p.PolicyId = ?
               GROUP BY p.SumInsured""",
            policy_id,
        )
        totals = _rows(cur)
        if not totals:
            return {"found": False, "policyId": policy_id}

        return {
            "found": True,
            "policyId": policy_id,
            "sumInsured": totals[0]["SumInsured"],
            "remainingSumInsured": totals[0]["RemainingSumInsured"],
            "claims": claims,
        }


if __name__ == "__main__":
    # Streamable HTTP so cloud agents (Foundry) can call it once deployed.
    # stateless_http + json_response: each request gets a plain JSON reply and no
    # server-side session, which suits tool calls and scale-to-zero hosting.
    # Local URL: http://127.0.0.1:8000/mcp
    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        json_response=True,
        stateless_http=True,
    )
