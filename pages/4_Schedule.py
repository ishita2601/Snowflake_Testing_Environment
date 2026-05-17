import streamlit as st
import pandas as pd

from utils.helpers import (
    run_query,
    exec_query,
    safe_str,
    format_score
)
# ============================================================
# SCHEDULE
# ============================================================
elif page == "Schedule":

    st.header("Schedule Tasks")

    projects_df = run_query("""
        SELECT DISTINCT PROJECT_NAME
        FROM CLAID_TEST.CONFIG
        WHERE IS_ACTIVE = TRUE
        ORDER BY PROJECT_NAME
    """)

    if projects_df.empty:
        st.warning("No active project configs found. Create one in Configuration first.")
        st.stop()  # intentional early exit

    project = st.selectbox("Project", projects_df["PROJECT_NAME"].tolist())
    cron    = st.text_input(
        "Cron expression (Asia/Kolkata timezone)",
        value="0 0 * * *",
        help="Format: minute hour day month weekday. Default = midnight daily."
    )

    st.caption("Common schedules: `0 0 * * *` = daily midnight | `0 */6 * * *` = every 6h | `*/30 * * * *` = every 30min")

    sp_proj = safe_str(project)
    task    = f"TASK_{project.replace(' ', '_').replace('-', '_')}"

    col_en, col_dis = st.columns(2)

    if col_en.button("Enable Schedule"):
        sp_cron = safe_str(cron)
        ok1 = exec_query(f"""
            CREATE OR REPLACE TASK CLAID_TEST.{task}
            WAREHOUSE = COMPUTE_WH
            SCHEDULE  = 'USING CRON {cron} Asia/Kolkata'
            AS CALL CLAID_TEST.SP_RUN_TESTS('{sp_proj}', 'SCHEDULED')
        """)
        ok2 = exec_query(f"ALTER TASK CLAID_TEST.{task} RESUME")
        if ok1 and ok2:
            st.success(f"Schedule enabled: `{cron}` for {project}")

    if col_dis.button("⏸ Disable Schedule"):
        ok = exec_query(f"ALTER TASK CLAID_TEST.{task} SUSPEND")
        if ok:
            st.warning(f"Schedule suspended for {project}.")

    # Run history for this project
    history = run_query(f"""
        SELECT RUN_ID, RUN_TIMESTAMP, TOTAL_TESTS, PASSED, FAILED,
               PASS_RATE, TRIGGERED_BY, TOTAL_DURATION_MS
        FROM CLAID_TEST.RUN_SUMMARY
        WHERE PROJECT_NAME = '{sp_proj}'
        ORDER BY RUN_TIMESTAMP DESC
        LIMIT 50
    """)

    if not history.empty:
        history["PASS_RATE"]     = history["PASS_RATE"].apply(format_score)
        history["RUN_TIMESTAMP"] = pd.to_datetime(history["RUN_TIMESTAMP"])

        st.subheader("Run History")
        st.dataframe(history, use_container_width=True)

        st.subheader("Pass Rate — Last 7 Runs")
        chart = history.head(7).sort_values("RUN_TIMESTAMP")
        st.line_chart(chart.set_index("RUN_TIMESTAMP")["PASS_RATE"])

    else:
        st.info("No runs found for this project yet.")
