CREATE OR REPLACE PROCEDURE CLAID_TEST.SP_RUN_TESTS(
    PROJECT_NAME VARCHAR,
    TRIGGER_TYPE VARCHAR DEFAULT 'MANUAL'
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
import uuid
import json
import traceback
from datetime import datetime

def run(session, PROJECT_NAME, TRIGGER_TYPE):

    run_id = str(uuid.uuid4())
    passed = 0
    failed = 0
    total_tests = 0
    start_time = datetime.utcnow()

    # ==========================
    # FETCH CONFIG
    # ==========================
    config_df = session.sql(f"""
        SELECT CONFIG_JSON
        FROM CLAID_TEST.CONFIG
        WHERE PROJECT_NAME = '{PROJECT_NAME}'
          AND IS_ACTIVE = TRUE
        ORDER BY UPDATED_AT DESC
        LIMIT 1
    """).collect()

    if not config_df:
        return f"No active config found for project: {PROJECT_NAME}"

    config = config_df[0]["CONFIG_JSON"]
    if isinstance(config, str):
        config = json.loads(config)

    schema_name = config.get("snowflake_schema")
    tests = config.get("tests") or []
    object_checks = config.get("object_exists") or []

    # ==========================
    # HELPERS
    # ==========================
    def safe(v):
        if v is None:
            return "NULL"
        if isinstance(v, (dict, list)):
            v = json.dumps(v)
        return "'" + str(v).replace("'", "''") + "'"

    def log_result(table, test_type, column, status, actual, expected, error):
        session.sql(f"""
            INSERT INTO CLAID_TEST.RUN_RESULTS (
                RUN_ID,
                PROJECT_NAME,
                TEST_TABLE,
                TEST_TYPE,
                TEST_COLUMN,
                STATUS,
                ACTUAL_VALUE,
                EXPECTED_VALUE,
                ERROR_MESSAGE,
                RUN_TIMESTAMP,
                DURATION_MS
            )
            VALUES (
                '{run_id}',
                '{PROJECT_NAME}',
                {safe(table)},
                {safe(test_type)},
                {safe(column)},
                {safe(status)},
                {safe(actual)},
                {safe(expected)},
                {safe(error)},
                CURRENT_TIMESTAMP(),
                NULL
            )
        """).collect()

    def normalize(r):
        try:
            if isinstance(r, str):
                return json.loads(r)
            return r
        except:
            return {"status": "FAIL", "error": "parse error"}

    # ==========================
    # RUN TABLE TESTS
    # ==========================
    for tblock in tests:
        table = tblock.get("table")
        checks = tblock.get("checks") or []

        for c in checks:
            total_tests += 1
            ttype = c.get("type")

            try:
                if ttype == "no_nulls":
                    r = normalize(session.call("CLAID_TEST.SP_NULL_CHECK", schema_name, table, c["column"]))

                elif ttype == "no_duplicates":
                    r = normalize(session.call("CLAID_TEST.SP_DUPLICATE_CHECK", schema_name, table, c["column"]))

                elif ttype in ["row_count", "row_count_min"]:
                    r = normalize(session.call(
                        "CLAID_TEST.SP_ROW_COUNT_CHECK",
                        schema_name,
                        table,
                        c.get("min", 0),
                        c.get("max", 999999)
                    ))

                elif ttype == "freshness":
                    r = normalize(session.call(
                        "CLAID_TEST.SP_FRESHNESS_CHECK",
                        schema_name,
                        table,
                        c["column"],
                        c["max_age_hours"]
                    ))

                elif ttype == "value_range":
                    r = normalize(session.call(
                        "CLAID_TEST.SP_VALUE_RANGE_CHECK",
                        schema_name,
                        table,
                        c["column"],
                        c["min"],
                        c["max"]
                    ))

                elif ttype == "referential_integrity":
                    r = normalize(session.call(
                        "CLAID_TEST.SP_REFERENTIAL_CHECK",
                        schema_name,
                        table,
                        c["fk_column"],
                        c["ref_table"],
                        c["ref_column"]
                    ))

                elif ttype == "schema_match":
                    r = normalize(session.call(
                        "CLAID_TEST.SP_SCHEMA_CHECK",
                        schema_name,
                        table,
                        c["expected_columns"]
                    ))

                elif ttype == "custom_sql":
                    r = normalize(session.call(
                        "CLAID_TEST.SP_CUSTOM_SQL_CHECK",
                        c["query"]
                    ))

                else:
                    r = {"status": "FAIL", "error": f"Unsupported test type: {ttype}"}

                status = r.get("status", "FAIL")

                log_result(
                    table,
                    ttype,
                    c.get("column"),
                    status,
                    r.get("actual"),
                    r.get("expected"),
                    r.get("error")
                )

                if status == "PASS":
                    passed += 1
                else:
                    failed += 1

            except Exception:
                failed += 1
                log_result(
                    table,
                    ttype,
                    c.get("column"),
                    "FAIL",
                    None,
                    None,
                    traceback.format_exc()
                )

    # ==========================
    # OBJECT CHECKS
    # ==========================
    for obj in object_checks:
        total_tests += 1

        try:
            r = normalize(session.call(
                "CLAID_TEST.SP_OBJECT_EXISTS",
                obj["type"],
                obj["name"]
            ))

            status = r.get("status", "FAIL")

            log_result(
                "OBJECT",
                "object_exists",
                obj["name"],
                status,
                r.get("actual"),
                r.get("expected"),
                r.get("error")
            )

            if status == "PASS":
                passed += 1
            else:
                failed += 1

        except Exception:
            failed += 1
            log_result(
                "OBJECT",
                "object_exists",
                obj.get("name"),
                "FAIL",
                None,
                None,
                traceback.format_exc()
            )

    # ==========================
    # SUMMARY
    # ==========================
    duration = int((datetime.utcnow() - start_time).total_seconds() * 1000)
    pass_rate = round((passed / total_tests) * 100, 2) if total_tests else 0

    session.sql(f"""
        INSERT INTO CLAID_TEST.RUN_SUMMARY
        VALUES (
            '{run_id}',
            '{PROJECT_NAME}',
            {total_tests},
            {passed},
            {failed},
            {pass_rate},
            CURRENT_TIMESTAMP(),
            {duration},
            '{TRIGGER_TYPE}'
        )
    """).collect()

    # ==========================
    # EMAIL ALERT LOGIC (FINAL FIXED)
    # ==========================
    try:
        current_status = "FAIL" if failed > 0 else "PASS"

        # Get previous run status safely
        prev_df = session.sql(f"""
            SELECT FAILED
            FROM CLAID_TEST.RUN_SUMMARY
            WHERE PROJECT_NAME = '{PROJECT_NAME}'
            ORDER BY RUN_TIMESTAMP DESC
            LIMIT 1 OFFSET 1
        """).collect()

        prev_status = "PASS"
        if prev_df:
            prev_failed = prev_df[0]["FAILED"]
            prev_status = "FAIL" if prev_failed > 0 else "PASS"

        # Decide when to send email
        send_email_flag = False

        if failed > 0:
            if TRIGGER_TYPE == "MANUAL":
                send_email_flag = True
            elif TRIGGER_TYPE == "SCHEDULED" and prev_status == "PASS":
                send_email_flag = True

        # ==========================
        # SEND EMAILS
        # ==========================
        if send_email_flag:

            # Fetch subscribed emails
            emails = session.sql(f"""
                SELECT EMAIL
                FROM CLAID_TEST.EMAIL_SUBSCRIPTIONS
                WHERE PROJECT_NAME = '{PROJECT_NAME}'
                  AND IS_ACTIVE = TRUE
            """).collect()

            # Fetch failed test details
            fail_list = session.sql(f"""
                SELECT TEST_TYPE, TEST_COLUMN, ACTUAL_VALUE
                FROM CLAID_TEST.RUN_RESULTS
                WHERE RUN_ID = '{run_id}'
                  AND STATUS = 'FAIL'
            """).collect()

            short_fail = "\n".join([
                f"{f['TEST_TYPE']} - {f['TEST_COLUMN']} → {f['ACTUAL_VALUE']}"
                for f in fail_list
            ])

            subject = f"🚨 CLAID ALERT: {PROJECT_NAME}"

            message = (
                f"Run ID: {run_id}\n"
                f"Status: {current_status}\n"
                f"Failed: {failed}/{total_tests}\n\n"
                f"Failures:\n{short_fail}"
            )

            # Send email to each subscriber
            for e in emails:
                email_id = e["EMAIL"]

                session.sql(f"""
                    CALL SYSTEM$SEND_EMAIL(
                        'EMAIL_INT',
                        '{email_id}',
                        '{subject}',
                        '{message.replace("'", "''")}'
                    )
                """).collect()

    except Exception as ex:
        print("EMAIL ERROR:", ex)

    return f"Run complete. {passed} passed, {failed} failed. RUN_ID={run_id}"
$$;
