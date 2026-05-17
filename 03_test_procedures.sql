-- ============================================
-- NULL CHECK (unchanged — correct)
-- ============================================
CREATE OR REPLACE PROCEDURE CLAID_TEST.SP_NULL_CHECK(
    schema_name VARCHAR,
    table_name VARCHAR,
    column_name VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session, schema_name, table_name, column_name):
    try:
        query = f"""
            SELECT COUNT(*) AS CNT
            FROM {schema_name}.{table_name}
            WHERE {column_name} IS NULL
        """
        cnt = session.sql(query).collect()[0]["CNT"]

        status = "PASS" if cnt == 0 else "FAIL"

        return {
            "status": status,
            "actual": cnt,
            "expected": 0,
            "error": None
        }

    except Exception as e:
        return {"status": "FAIL", "actual": None, "expected": 0, "error": str(e)}
$$;
-- ============================================
-- DUPLICATE CHECK (unchanged — correct)
-- ============================================
CREATE OR REPLACE PROCEDURE CLAID_TEST.SP_DUPLICATE_CHECK(
    schema_name VARCHAR,
    table_name VARCHAR,
    column_name VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session, schema_name, table_name, column_name):
    try:
        query = f"""
            SELECT COUNT(*) AS CNT
            FROM (
                SELECT {column_name}
                FROM {schema_name}.{table_name}
                GROUP BY {column_name}
                HAVING COUNT(*) > 1
            )
        """

        cnt = session.sql(query).collect()[0]["CNT"]

        return {
            "status": "PASS" if cnt == 0 else "FAIL",
            "actual": cnt,
            "expected": 0,
            "error": None
        }

    except Exception as e:
        return {"status": "FAIL", "actual": None, "expected": 0, "error": str(e)}
$$;
-- ============================================
-- ROW COUNT CHECK (unchanged — correct)
-- ============================================
CREATE OR REPLACE PROCEDURE CLAID_TEST.SP_ROW_COUNT_CHECK(
    schema_name VARCHAR,
    table_name VARCHAR,
    min_val INTEGER,
    max_val INTEGER
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session, schema_name, table_name, min_val, max_val):
    try:
        query = f"SELECT COUNT(*) AS CNT FROM {schema_name}.{table_name}"
        cnt = session.sql(query).collect()[0]["CNT"]

        if min_val <= cnt <= max_val:
            return {"status": "PASS", "actual": cnt, "expected": f"{min_val}-{max_val}", "error": None}
        else:
            return {"status": "FAIL", "actual": cnt, "expected": f"{min_val}-{max_val}", "error": None}

    except Exception as e:
        return {"status": "FAIL", "actual": None, "expected": None, "error": str(e)}
$$;
-- ============================================
----RANGE CHECK--------------------
CREATE OR REPLACE PROCEDURE CLAID_TEST.SP_VALUE_RANGE_CHECK(
    schema_name VARCHAR,
    table_name VARCHAR,
    column_name VARCHAR,
    min_val FLOAT,
    max_val FLOAT
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session, schema_name, table_name, column_name, min_val, max_val):
    try:
        query = f"""
            SELECT COUNT(*) AS CNT
            FROM {schema_name}.{table_name}
            WHERE {column_name} < {min_val}
               OR {column_name} > {max_val}
               OR {column_name} IS NULL
        """

        cnt = session.sql(query).collect()[0]["CNT"]

        return {
            "status": "PASS" if cnt == 0 else "FAIL",
            "actual": cnt,
            "expected": f"No values outside range {min_val}-{max_val}",
            "error": None
        }

    except Exception as e:
        return {"status": "FAIL", "actual": None, "expected": None, "error": str(e)}
$$;
-- ============================================
-- REFERENTIAL CHECK (unchanged — correct)
-- ============================================
CREATE OR REPLACE PROCEDURE CLAID_TEST.SP_REFERENTIAL_CHECK(
    schema_name VARCHAR,
    table_name VARCHAR,
    fk_column VARCHAR,
    ref_table VARCHAR,
    ref_column VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session, schema_name, table_name, fk_column, ref_table, ref_column):
    try:
        query = f"""
            SELECT COUNT(*) AS CNT
            FROM {schema_name}.{table_name} t
            LEFT JOIN {schema_name}.{ref_table} r
            ON t.{fk_column} = r.{ref_column}
            WHERE r.{ref_column} IS NULL
        """

        cnt = session.sql(query).collect()[0]["CNT"]

        return {
            "status": "PASS" if cnt == 0 else "FAIL",
            "actual": cnt,
            "expected": 0,
            "error": None
        }

    except Exception as e:
        return {"status": "FAIL", "actual": None, "expected": 0, "error": str(e)}
$$;
-- ============================================
-- FRESHNESS CHECK (FIXED + STANDARDIZED)
-- ============================================
CREATE OR REPLACE PROCEDURE CLAID_TEST.SP_FRESHNESS_CHECK(
    schema_name VARCHAR,
    table_name VARCHAR,
    timestamp_column VARCHAR,
    max_age_hours INTEGER
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session, schema_name, table_name, timestamp_column, max_age_hours):
    try:
        query = f"""
            SELECT MAX({timestamp_column}) AS LAST_TS
            FROM {schema_name}.{table_name}
        """

        last_ts = session.sql(query).collect()[0]["LAST_TS"]

        if last_ts is None:
            return {"status": "FAIL", "actual": None, "expected": f"<= {max_age_hours}h", "error": "No timestamp found"}

        query_age = f"""
            SELECT DATEDIFF('hour', '{last_ts}', CURRENT_TIMESTAMP()) AS AGE_HOURS
        """

        age = session.sql(query_age).collect()[0]["AGE_HOURS"]

        return {
            "status": "PASS" if age <= max_age_hours else "FAIL",
            "actual": age,
            "expected": max_age_hours,
            "error": None
        }

    except Exception as e:
        return {"status": "FAIL", "actual": None, "expected": None, "error": str(e)}
$$;
--------------------------------------------------------
-----OBJECT EXISTS CHECK--------------------------------
--------------------------------------------------------
CREATE OR REPLACE PROCEDURE CLAID_TEST.SP_OBJECT_EXISTS(
    object_type VARCHAR,
    object_name VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session, object_type, object_name):
    try:
        if object_type == "view":
            query = f"SHOW VIEWS LIKE '{object_name}'"
        elif object_type == "task":
            query = f"SHOW TASKS LIKE '{object_name}'"
        elif object_type == "stored_procedure":
            query = f"SHOW PROCEDURES LIKE '{object_name}'"
        else:
            raise Exception("Unsupported object type")

        result = session.sql(query).collect()

        return {
            "status": "PASS" if len(result) > 0 else "FAIL",
            "actual": len(result),
            "expected": 1,
            "error": None
        }

    except Exception as e:
        return {"status": "FAIL", "actual": None, "expected": 1, "error": str(e)}
$$;
-- ============================================
-- SCHEMA CHECK
-- ============================================
CREATE OR REPLACE PROCEDURE CLAID_TEST.SP_SCHEMA_CHECK(
    schema_name VARCHAR,
    table_name VARCHAR,
    expected_columns VARIANT
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session, schema_name, table_name, expected_columns):
    try:
        import json

        # ==========================
        # Resolve DB + Schema
        # ==========================
        parts = schema_name.split(".")

        if len(parts) == 2:
            db, schema = parts
        else:
            db = session.get_current_database()
            schema = schema_name

        # ==========================
        # Fetch ACTUAL schema
        # ==========================
        query = f"""
            SELECT COLUMN_NAME, DATA_TYPE
            FROM {db}.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = '{schema}'
              AND TABLE_NAME = '{table_name.upper()}'
        """

        rows = session.sql(query).collect()

        actual_schema = {
            r["COLUMN_NAME"]: r["DATA_TYPE"]
            for r in rows
        }

        # ==========================
        # Parse EXPECTED schema
        # ==========================
        if isinstance(expected_columns, str):
            expected_schema = json.loads(expected_columns)
        else:
            expected_schema = expected_columns or {}

        # ==========================
        # CHECKS
        # ==========================

        # Missing columns
        missing = [
            col for col in expected_schema
            if col not in actual_schema
        ]

        # Extra columns
        extra = [
            col for col in actual_schema
            if col not in expected_schema
        ]

        # Data type mismatch
        type_mismatch = [
            col for col in expected_schema
            if col in actual_schema and
            expected_schema[col].upper() not in actual_schema[col].upper()
        ]

        # ==========================
        # FINAL STATUS
        # ==========================
        if len(missing) == 0 and len(extra) == 0 and len(type_mismatch) == 0:
            status = "PASS"
        else:
            status = "FAIL"

        # ==========================
        # RETURN RESULT
        # ==========================
        return {
            "status": status,
            "actual": {
                "missing": missing,
                "extra": extra,
                "type_mismatch": type_mismatch
            },
            "expected": expected_schema,
            "error": None
        }

    except Exception as e:
        return {
            "status": "FAIL",
            "actual": None,
            "expected": None,
            "error": str(e)
        }
$$;
-- CUSTOM SQL CHECK (unchanged — correct) -- ============================================
CREATE OR REPLACE PROCEDURE CLAID_TEST.SP_CUSTOM_SQL_CHECK(
    assertion_query VARCHAR
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session, assertion_query):
    try:
        result = session.sql(assertion_query).collect()

        cnt = result[0][0] if result else 0

        return {
            "status": "PASS" if cnt == 0 else "FAIL",
            "actual": cnt,
            "expected": "0 violations (AMOUNT should be > 100)",
            "error": None
        }

    except Exception as e:
        return {"status": "FAIL", "actual": None, "expected": 0, "error": str(e)}
$$;
