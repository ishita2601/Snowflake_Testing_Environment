import streamlit as st
import pandas as pd

from utils.helpers import (
    run_query,
    exec_query,
    format_score,
    color_rows
)

from utils.snowflake import session
# ============================================================
# TEST RESULTS
# ============================================================
elif page == "Test Results":

    st.header("Test Results Dashboard")

    runs = run_query("""
        SELECT RUN_ID, PROJECT_NAME, RUN_TIMESTAMP
        FROM CLAID_TEST.RUN_SUMMARY
        ORDER BY RUN_TIMESTAMP DESC
    """)

    if runs.empty:
        st.warning("No runs found")
        st.stop()

    runs["LABEL"] = runs["PROJECT_NAME"] + " | " + runs["RUN_TIMESTAMP"].astype(str)

    selected = st.selectbox("Select Run", runs["LABEL"])
    run_id = runs[runs["LABEL"] == selected]["RUN_ID"].iloc[0]
    project_name = runs[runs["LABEL"] == selected]["PROJECT_NAME"].iloc[0]

    results = run_query(f"""
        SELECT *
        FROM CLAID_TEST.RUN_RESULTS
        WHERE RUN_ID = '{run_id}'
    """)

    if results.empty:
        st.warning("No results found")
        st.stop()

    results["TEST_COLUMN"] = results["TEST_COLUMN"].fillna("TABLE LEVEL")
    results["ACTUAL_VALUE"] = results["ACTUAL_VALUE"].fillna("—")
    results["EXPECTED_VALUE"] = results["EXPECTED_VALUE"].fillna("—")
    results["ACTUAL_VALUE"] = results["ACTUAL_VALUE"].apply(format_score)

    def color_rows(row):
        if row["STATUS"] == "PASS":
            return ["background-color:#d4edda"] * len(row)
        return ["background-color:#f8d7da"] * len(row)

    st.subheader("Test Results")
    st.dataframe(results.style.apply(color_rows, axis=1), use_container_width=True)

    # ============================
    # SUMMARY
    # ============================
    total = len(results)
    passed = len(results[results["STATUS"] == "PASS"])
    failed = len(results[results["STATUS"] == "FAIL"])
    pass_rate = round((passed / total) * 100, 2)

    col1, col2, col3 = st.columns(3)
    col1.metric("Total", total)
    col2.metric("Passed", passed)
    col3.metric("Failed", failed)

    st.subheader(f"Pass Rate: {pass_rate}%")

    # ============================
    # FAILURE INSIGHTS
    # ============================
    st.subheader("Failure Insights")

    failures = results[results["STATUS"] == "FAIL"]
    cortex_explanations = []

    if not failures.empty:
        for _, row in failures.iterrows():

            prompt = f"""
            Explain this failed test in simple business terms:

            Test Type: {row['TEST_TYPE']}
            Column: {row['TEST_COLUMN']}
            Actual: {row['ACTUAL_VALUE']}
            Expected: {row['EXPECTED_VALUE']}
            Error: {row['ERROR_MESSAGE']}
            """

            explanation = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large',
            $$ {prompt} $$
            )
            """).collect()[0][0]

            cortex_explanations.append({
                "test_type": row["TEST_TYPE"],
                "column": row["TEST_COLUMN"],
                "actual": row["ACTUAL_VALUE"],
                "expected": row["EXPECTED_VALUE"],
                "explanation": explanation
            })

            st.error(f"""
{row['TEST_TYPE']} | {row['TEST_COLUMN']}
{explanation}
""")

    # ============================
    # EMAIL ALERTS
    # ============================
    st.subheader("Email Alerts")

    alert_email = st.text_input("Enter Email", key="alert_email")

    col1, col2 = st.columns(2)

    if col1.button("Subscribe"):
        exec_query(f"""
            CALL CLAID_TEST.SP_ADD_EMAIL_SUBSCRIPTION(
                '{project_name}',
                '{alert_email}'
            )
        """)
        st.success("Subscribed")

    if col2.button("Unsubscribe"):
        exec_query(f"""
            CALL CLAID_TEST.SP_UNSUBSCRIBE_EMAIL(
                '{project_name}',
                '{alert_email}'
            )
        """)
        st.warning("Unsubscribed")

    # ============================
    # EMAIL + CSV DOWNLOAD FIX
    # ============================
    st.markdown("Send Detailed Failure Email")

    if st.button("Send Email Report"):

        failure_text = ""
        for f in cortex_explanations:
            failure_text += f"""
--------------------------------
Type: {f['test_type']}
Column: {f['column']}
Actual: {f['actual']}
Expected: {f['expected']}
Explanation:
{f['explanation']}
"""

        csv_data = results.to_csv(index=False)

        download_link_text = f"CSV Report is available in Streamlit download from there."

        email_body = f"""
CLAID TEST REPORT

Project: {project_name}
Run ID: {run_id}

FAILURES:
{failure_text}

{download_link_text}
"""

        exec_query(f"""
            CALL SYSTEM$SEND_EMAIL(
                'EMAIL_INT',
                '{alert_email}',
                'CLAID TEST REPORT',
                $$ {email_body} $$
            )
        """)

        st.success("Email sent successfully")

    # ============================
    # REAL DOWNLOAD BUTTON (THIS IS THE FIX)
    # ============================
    st.download_button(
        label="⬇ Download CSV Report",
        data=results.to_csv(index=False),
        file_name=f"{run_id}_report.csv",
        mime="text/csv"
    )
